# 12 Circle Fitness — QA Closure Standard

**Wave 0 deliverable. What "closed" means, and what it does not.**
**Date:** 2026-08-24 · Governs every status change in [`MASTER_REMEDIATION_REGISTRY.md`](MASTER_REMEDIATION_REGISTRY.md)

---

## 1. The problem this document exists to prevent

The word **"fixed"** has been used across this programme to mean at least five different
things. Two of them are not fixes.

This is not a hypothetical concern. **Five findings that a prior phase reported as closed
were later found open, and in three cases the closure itself introduced the regression**
(`MASTER_REMEDIATION_REGISTRY.md` §4.2):

- Migration 116 published an authorization wrapper; migration **119** replaced it with a
  bare `SECURITY DEFINER` body and re-granted `EXECUTE`. 116's own header warned about
  exactly this escape. Migration 122 caught two related halves and not this one.
- Migration 115 made PAR-Q risk server-authoritative — and made it **unrecordable**,
  because the classifier throws on the three flags it appends as untyped literals.
- Phase 2 closed the orphaned-session defect through the happy path; the error path
  resurrects it, and the guard written to protect the fix **does not read the file where
  the defect lives**.
- Phase 2 removed every `catch` from the workout providers; the swallow **moved one layer
  down** into the service, where nine providers sit on top of it.

Every one of these passed a plausible closure review. **The standard below is written
specifically so that each of them would have failed it.**

---

## 2. The evidence ladder

Five states. They are **not** synonyms and must never be used interchangeably in a report,
a commit message, a status board or a conversation.

| State | Means | Proves | Does **not** prove |
|---|---|---|---|
| **FIXED IN CODE** | The change exists in a committed diff | Someone wrote the intended change | That it compiles in context, that it is correct, that it deployed, or that anything exercises it |
| **VERIFIED IN CI** | An automated check fails against the pre-fix tree and passes against the post-fix tree, **in CI** | The change has a standing guard that a future edit cannot silently undo | That the deployed environment behaves as the code implies |
| **FIXED ON QA** | The migration, function or configuration is applied to QA and the object exists in the live catalog | The change reached the environment | That it behaves correctly, or that authorization composes as intended |
| **VERIFIED LIVE** | A real request against QA reproduces the *secure/correct* behaviour, **and the same probe demonstrably failed before the fix** | Policies, grants, triggers and PostgREST **compose** as intended | That the user-facing path reaches it, or that no collateral regression occurred |
| **VERIFIED END-TO-END** | The full chain runs — UI → state → service → authorization → API/function → database → persistence → response → UI state — with the correct **failure** behaviour, and the regression suite is green | The feature works as a product | Nothing further; this is the terminal state |

### 2.1 Which states a finding needs

| Finding class | Required states |
|---|---|
| **Security / authorization** | FIXED IN CODE · FIXED ON QA · **VERIFIED LIVE** · VERIFIED IN CI |
| **Data contract / schema** | FIXED IN CODE · FIXED ON QA · VERIFIED IN CI (`test:contract` with the allowlist entry removed) · VERIFIED LIVE where a read path exists |
| **Error contract / false success** | FIXED IN CODE · VERIFIED IN CI (a test asserting the *failure* path) · **VERIFIED END-TO-END** for any user-facing success state |
| **AI / safety input** | all five. A safety input is never closed on source review |
| **Billing / entitlement** | FIXED IN CODE · VERIFIED IN CI · **VERIFIED LIVE** against Stripe **test mode** · VERIFIED END-TO-END for anything that moves money |
| **Release / environment** | FIXED IN CODE · **VERIFIED IN CI** — an environment guard that is not mechanized is not a guard |
| **Product integrity / UI reachability** | FIXED IN CODE · VERIFIED IN CI · VERIFIED END-TO-END (a human or a driver reached the surface) |
| **Hygiene / P3** | FIXED IN CODE · VERIFIED IN CI where a guard is cheap |

**`VERIFIED_CLOSED` requires every state its class demands. There are no partial closures
and no exceptions granted at implementation time.**

---

## 3. The twelve-step closure procedure

Adapted from the programme brief and made specific to this repository.

1. **Reproduce before the fix, where safe.** Record the exact BEFORE output — status code,
   error code, row count, rendered string. "It was broken" is not a BEFORE state.
   *Where reproducing means re-opening a live hole on a shared QA project — disabling RLS,
   re-granting `anon` on live health data — **do not do it.** Record the catalog state and
   the prior workstream's reproduction instead, and say so explicitly. Phase 1 handled
   D-03 exactly this way and was right to.*
2. **Write the guard first, and watch it fail.** The test must fail against the pre-fix
   tree. A guard written after the fix has never been observed to catch anything.
3. **Implement the smallest correct root-cause fix.** Not the smallest change — the
   smallest change *that addresses the root cause in §1 of the registry*. Symptom patches
   are rejected at review.
4. **Add or update the regression test**, tagged with the canonical finding ID.
5. **Run the relevant local suites** and record the counts.
6. **Run the analyzer/compiler.** `flutter analyze` must not gain an error.
7. **Apply the migration to QA only when the wave authorizes it**, and never before
   step 8.
8. **Verify the target is QA.** Independently — read the linked ref, do not trust a
   filename, an environment variable, or a script's name. *Three scripts in this
   repository are named `qa_*` or `live_*` and target production.*
9. **Run the live QA assertion** and record the AFTER output in the same form as the
   BEFORE.
10. **Re-run the full regression suite** and check for collateral regressions — including
    suites in other domains. The mobile baseline is **730 passed / 9 skipped / 0 failed**.
11. **Record the evidence** in the registry row: BEFORE, remediation, AFTER, exact files
    and migrations changed, test result, live result, **production-untouched
    confirmation**, and remaining limitations.
12. **Mark `VERIFIED_CLOSED` only when §2.1's required states all exist.**

---

## 4. What does not close a finding

Stated as prohibitions because each has occurred in this programme.

| Not a closure | Why |
|---|---|
| **"The code changed."** | That is `FIXED IN CODE`, one of five states. Say which state you mean |
| **A static test asserting migration text.** | `SEC-020`…`SEC-024` assert that a `REVOKE` appears in a file. They **cannot** assert the database's actual grant state. Necessary, never sufficient, for a security finding |
| **A guard that does not read the file where the defect lives.** | `EC-G1` asserts `workout_provider.dart` contains no `catch`. The defect moved to the screens and to the service. The guard passes. **The defect is live** |
| **A ratchet that cannot see the defect's shape.** | `EC-G5` counts `catch` blocks. Riverpod swallows via `error: (_,__) =>` and `.valueOrNull`, which contain no `catch`. ~150 sites are invisible to it |
| **A test that executes a copy of the product.** | 259 tests — 37% of the Flutter suite — define the logic inside the test file and assert against the copy. They are green whatever the app does. **Convert them, never delete them:** deleting lowers the count without raising the confidence |
| **A passing suite that has never run in CI.** | The 188-assertion live security suite is the best test asset in the repository and **has not executed since Phase 1**. A guard nobody runs protects nobody — an argument the suite's own README already makes |
| **Fixtures that exercise the fix.** | QA's check-in fixtures write the **opposite column family** from the application's writer, so QA looks populated while the real path produces unreadable rows. **Fixtures must be written against the writer, never against the reader** |
| **A green build after weakening a test.** | Never weaken a test to get green. If a test must change, the change is a reviewed decision recorded in the finding's evidence |
| **An allowlist entry.** | `known-violations.json` and `EC-G2`'s phantom-table allowlist are **shrinking** lists. An entry is a recorded defect, not a closure. Both are checked in **both directions**, so an entry removed without the fix — or a fix without the removal — fails |
| **"It works on my machine."** | See CI, above |
| **A source review of a safety input.** | `[]` from a failed read and `[]` from "this member has none" are the same value at review time and different values in production. Safety inputs close live, or not at all |
| **Closing a canonical finding.** | An alias acquires no status from its canonical's closure — and loses none either. The alias map is **REFERENCE-ONLY**; see §4.1 |

### 4.1 The alias map is REFERENCE-ONLY

**Owner decision, recorded here by authorization of 2026-10-11.** The content is not new — it
was ruled at `V5_PROGRAMME_DEFINITION` §8.15 (`EC-01·Q1`) and extended at §19.4 (`EC-01·Q2`),
which recorded that this file should carry the definition. This entry records it; it decides
nothing further.

> **The alias map is REFERENCE-ONLY.** An alias is a **de-duplication pointer**. Closing a
> canonical finding **neither discharges nor preserves** an alias's substantive condition:
> **substantive status must be determined separately for each.**

And the extension, from §19.4:

> A canonical's closure class **does not bind** an alias of a different class. Each alias's
> substantive status **and its evidence standard** follow its own subject matter.

**What follows from it, and what does not.** A canonical may remain correctly closed on its own
class while an alias of a different class remains open — that is not a contradiction in the
registry, it is the rule working. Disposing of an alias is a **separate act** requiring its own
evidence at its own class. An alias is therefore neither remediated nor re-opened by a
canonical's closure; it stays as the registry records it until that separate act is performed.

---

## 5. Special standards

### 5.1 Safety findings

A finding is a **safety finding** if it touches injuries, contraindications, PAR-Q risk
and flags, allergies, dietary restrictions, recovery state, women's-health constraints, or
the authorization/identity of the subject a decision is made about.

Additional requirements beyond §3:

- **A negative test and a positive test.** Force the input to *fail* → the decision must
  refuse. Force the input to be *legitimately empty* → the decision must proceed. **Both
  are required.** Without the second, a rule-S fix that over-triggers looks identical to
  one that works.
- **Fail closed means fail visibly.** A refusal that is silent is a different defect, not
  a fix.
- **No substituted value.** `[]`, `null`, `false`, `0`, `"general"`, `"low"`, `"none"` may
  not stand in for a failed safety read unless the product contract explicitly defines
  that value as valid — and if it does, cite the contract in the evidence.
- **A clinical-policy finding cannot be closed by engineering** (see
  [`MASTER_PRODUCT_DECISIONS.md`](MASTER_PRODUCT_DECISIONS.md) group D). Its *mechanical*
  half may close independently and must say so.

### 5.2 Security findings

- **Live evidence is mandatory** wherever it is feasible and safe.
- **Destructive or security-sensitive probes use transaction rollback** where possible.
  Where they cannot, the probe is not run and the limitation is recorded.
- **Test the class, not the instance.** `F-J-01` existed because `d04-rpc-execution.mjs`
  asserted four of the five 116 wrappers individually rather than all five as a class.
  A closure that pins only the instance is incomplete.
- **A closure that redefines a database object must prove it preserved every property the
  object carried** — `search_path`, authorization wrapper, grants, triggers, comments.
  This is Gate 0 row 0.14 and it is the class fix for §4.2.

### 5.3 Regressions

When a closed finding reopens:

1. **Re-open the existing row.** Do not file a new ID — the history is the point.
2. Record **which change** regressed it and **which guard should have caught it**.
3. Fix the finding **and** the guard. A regression closed without strengthening the guard
   is closed at the same confidence it was closed at last time.
4. Add the regression to the registry's §4.2 table permanently, even after closure.

### 5.4 Findings blocked on a decision

- Split the row into a **mechanical half** and a **policy half**, and schedule the
  mechanical half immediately. 31 of the 73 decisions have such a half.
- The mechanical half closes on its own evidence. The row stays `BLOCKED_DECISION` until
  both close.
- **Never guess the policy to unblock the mechanics.** Ship the mechanics under a stated
  assumption, and state the assumption in the evidence.

### 5.5 Findings blocked on the environment

- `BLOCKED_ENVIRONMENT` requires a named blocker ID from the registry §8 and a named
  owner. "We don't have credentials" without an owner is not a blocker, it is an unassigned
  task.
- A finding may **not** be closed on source review because its environment is missing. It
  stays blocked. *This is why zero of the AI findings can close before Wave 5.*

---

## 6. Production statement — required in every closure

Every closure record carries, verbatim:

> **Production `nxdbooufqzkpslkcogxc` was not contacted.** No REST, RPC, Auth, Storage,
> Realtime or Edge Function request was issued to it. No migration was applied, reverted or
> pushed to it. No Edge Function was deployed to it. The linked project remained
> `eyqtldjqpgpljlqvpowh` throughout.

If any part of that is untrue, the closure is **not recorded** — the deviation is escalated
first. A deliberate near-contact (for example, running a harness's refusal guard against
the production URL to prove it refuses) is **disclosed in full**, including which
credentials were present, exactly as Workstream L did.

---

## 7. QA hygiene — required in every closure that writes

- Every row written to QA is enumerated and removed, and **the removal is verified by a
  read as every relevant role**, not assumed from a `204`.
- Fixture identities created by a suite are torn down by the same suite.
- No probe residue may remain when a wave exits. *Workstream D's Phase 0 found
  pre-existing `QA-PROBE-ANON` rows in `weekly_checkins` — evidence that a hole had already
  been exercised by an unknown actor. Residue is not only untidy; it is indistinguishable
  from an intrusion.*

---

## 8. Working-tree discipline

Restated because this programme runs with concurrent sessions in one tree.

- Never `reset`, `stash`, `clean`, `checkout` unrelated files, discard changes, or revert
  another session's work.
- Never delete a file because it appears unused. **`workout_restoration.dart` and
  `workout_contract.dart` are untracked, look disposable, and the app does not compile
  without them.**
- Never rewrite a migration in place unless the wave plan explicitly authorizes it.
  **Prefer additive forward migrations.** Fifteen historical migrations are already edited
  in place, and carrying those deltas forward is a P0 in its own right.
- If another session changes a file mid-work: **stop, re-read its current contents,
  reconcile, and make the smallest additive change possible.** Treat concurrent work as
  authoritative unless proven otherwise.
- **Migration numbers are assigned in [`MASTER_REMEDIATION_WAVES.md`](MASTER_REMEDIATION_WAVES.md) §0.2**, not chosen at
  implementation time.

---

## 9. The invariants a closure must not violate

Every closure is checked against these. A fix that violates one is not a fix.

| # | Invariant |
|---|---|
| **I-1 · Success state** | No user-facing success state may be displayed unless authoritative evidence confirms the underlying operation succeeded. Not "Workout Complete" on a failed persist. Not "Invite sent" on a failed dispatch. Not "You're registered" on a failed registration. Not "Connected" on an incomplete OAuth. Not "Switched to Free" on a failed cancellation. **And never demo data presented as the user's own** |
| **I-2 · Identity** | Never use a human-readable label as authoritative identity. Exercise name ≠ exercise identity. Workout title ≠ workout identity. Coach name ≠ coach identity. Ticket display code ≠ registration identity. Use stable ids |
| **I-3 · Safety input** | The AI and the engine must never receive a silently degraded safety input and continue as though it were valid. **Fail closed** |
| **I-4 · Entitlement** | The client UI is never the authority. The server decides who may consume, what, how much, whether credits remain, whether the subscription is active, whether a retry is duplicate, and whether access continues after a payment failure |
| **I-5 · Empty vs unknown** | An empty value is an answer. It must never be a symptom. If a caller cannot distinguish "there is nothing" from "I could not find out", the contract is broken regardless of what the code returns |
| **I-6 · The engine decides** | The deterministic engine is authoritative for prescription. AI explains, contextualizes, summarizes and drafts for review. **No layer — including the presentation layer — may invent a prescription** |
| **I-7 · Provenance** | Every recommendation produces a decision trace that is complete enough to replay. A trace recorded over silently-degraded inputs is not an audit record |
| **I-8 · Immutable history** | Completed history is never rewritten. Corrections go through the explicit, audited correction path |
| **I-9 · Production isolation** | Production is not contacted, and a script is not safe because its filename says QA |

---

## 10. The one-line test

Before writing `VERIFIED_CLOSED`, answer this, in writing, in the registry row:

> **If this defect were reintroduced tomorrow by a plausible, well-intentioned change,
> what exactly goes red, and where does someone see it?**

If the answer is "someone would notice", "a reviewer would catch it", or "the local suite
would fail if someone ran it" — **the finding is not closed.** It is `REMEDIATED`, and the
guard is the remaining work.

*Four guards in this repository were written for a specific defect and cannot detect it.
Two of those defects are live in the tree right now. This question is the check that would
have caught all four.*
