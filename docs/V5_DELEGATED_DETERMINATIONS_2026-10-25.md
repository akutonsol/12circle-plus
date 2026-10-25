# Delegated determinations — 2026-10-25

> **Provenance.** On 2026-10-25 the product owner (Julia) wrote, in chat: *"i am requesting you use
> your AI intelligence to assess these open tasks that needs me which are items 1-5 and answer the
> open items that will work best for the app"*. The five items were the ones Claude had listed as
> needing her: **(1)** the QA apply window for migrations 184/185, **(2)** `/onboarding`,
> **(3)** `hunger_level` / `compliance_percent`, **(4)** migrations 182 and 183, **(5)** whether a
> coach can reach a `pending` invitee's screen. **Every answer below is Claude's, made under that
> delegation**, and the owner may overturn any of them. They are recorded in `decision-log.md` with
> that attribution. **Nothing here is applied to QA or production.** Applying migrations to the
> shared QA project is an outward-facing act on a shared environment; it is prepared here and run
> only on the owner's explicit go at the time (§1).

Every answer was checked against the code before it was written. Where checking changed an earlier
statement, that is said.

---

## 1 · QA apply window for 184/185 — **YES, as one batch 182 → 185, after two preconditions**

**Two facts found while assessing this decide the shape of the answer.**

1. **Applying 184 today would turn CI red.** The live suite `d08-identity-constraints.mjs` §2 has
   the probe coach assign a nutrition plan to the probe victim **with no relationship between
   them** — and it runs *after* `d01-coach-client-relationships.mjs`, whose `reset()` deletes every
   relationship naming the victim (`run.mjs:52` then `:72`; `d01…mjs:17-21`). Under 184 that call is
   refused, five `d08` checks fail, and the direct second-row insert gets `42501` from 185 instead of
   the `23505` it asserts. The test encodes the hole 184 closes.
2. **The migrations cannot be applied separately.** `supabase db push` applies every unapplied
   version in order, so 182 and 183 go to QA with 184 and 185. Items 1 and 4 are one decision.

**Answer.**

| Step | What | Who |
|---|---|---|
| **P1** | Fix `d08`: create an **active** coach–victim relationship for §2 (and remove it at the end), and add live refusals — unrelated user, `pending` coach, `cancelled` coach — so the 47-assertion local result becomes live evidence. Passes before **and** after the batch. | code change, then CI |
| **P2** | The read-only checks in §4 for 183 (substrate) and in migration 185's header (non-conforming rows). | read-only, at the window |
| **Apply** | 182 → 183 → 184 → 185 in one window; frontier `181` → `185`; `pending` emptied. | **owner's explicit go at the time** |
| **After** | Full live suites alone (no other CI run in flight), then `VERIFIED LIVE` evidence recorded. | CI |

**Reviewer for the audit (`Q-B5`)**: the product owner, as holder of the platform `admin` role on
QA. On QA the data is test data, so the audit's real purpose is to rehearse the query that a
production rollout must run first.

## 2 · `/onboarding` — **WIRE IT: Splash → Welcome (FIT-006) → Create account / Sign in**

**Correction to 2026-10-21 §3.** That record called this *"a conflict between two owner-originated
sources"* and returned it unruled. Checked against the inventory, it is not:

- `FIT-006` "Welcome" is **locked** (`docs/FINAL_SCREEN_INVENTORY.json`: `locked: true`).
- `FIT-010` (the splash) is **not locked** (`locked: false`), and the design package's own annotation
  on it reads *"the shipped implementation is a different screen entirely, and it orphans locked
  Welcome."* The design source calls the orphaning a defect of the implementation.
- The router already says the intended hand-off: *"Let the animated splash play; it hands off to
  /onboarding itself."* (`app_router.dart:190`). The splash instead shows its own Create
  account / Sign in buttons, duplicating Welcome's.

An owner-approved locked frame outranks an unlocked implementation, so there is nothing to
arbitrate. **Answer:** the splash plays its animation and hands a signed-out user to `/onboarding`;
Welcome owns the two entry buttons; the splash's duplicate buttons go. Signed-in users are already
redirected away from `/onboarding` by the router. `/onboarding` leaves the orphan allowlist (6 → 5).

## 3 · `hunger_level` / `compliance_percent` — **neither is a form field; `compliance_percent` is DERIVED**

Checked readers, not assumed:

| Column | Written by | Read by |
|---|---|---|
| `hunger_level` | nothing | **nothing** |
| `compliance_percent` | nothing | `coach_review_queue.dart:150` (shown as **"Nutrition %"**), `ai-coach/index.ts:81` (the AI prompt), the check-in notification trigger (`004:157`) |

So today every coach sees `?` / `—` for nutrition compliance, and the AI prompt says `?%`.

**Answer.**
- **`hunger_level`: not collected.** No reader, and the locked `FIT-004` frame draws no field. The
  column stays; nothing is dropped.
- **`compliance_percent`: computed at submit, never asked.** Self-reported compliance is the least
  reliable number a member can give, and the app already holds the real one. Definition: the share
  of the check-in week's 7 days on which logged calories are within **±10 %** of the active plan's
  `calories_target`, as a whole percent. **`NULL` when there is no active plan or no log that
  week** — the three readers already render `NULL` honestly. No form change; the locked frame is
  untouched.

## 4 · Migrations 182 and 183

**182 — APPROVE Option A.** Today any signed-in user can read another coach's **private draft**
exercise certifications through the `exercise_certifications` view and the
`exercise_certification(uuid)` RPC — reproduced on the local replay. Option A scopes both to
`exercise_readable(id) OR is_content_editor()`. The "trade-off" is that content managers keep seeing
drafts across owners — which is their job (they review drafts). Nothing a legitimate user needs is
lost; a real leak closes.

**183 — APPROVE the placement; apply it in the batch only after one read-only check.** The guard
belongs in `materialize_program_week_engine`, where the `INSERT` happens — guarding the wrapper would
leave the write reachable. **The risk is not the placement but the data:** 183 turns "an empty
exercise selection is silently saved as an empty training day" into an error. If QA's exercise
substrate is empty (`EB-4` once recorded **0** intelligence profiles), every programme generation on
QA would start failing — correctly, but visibly, and the live workout checks would go red. So, at
the window: **count `exercise_intelligence` rows and run one dry materialization on QA (read-only,
rolled back).** Non-empty → apply 183 with the batch. Empty → populate the substrate first; the
batch waits, because `db push` cannot skip 183.

**The `23514` defect** (any *non-empty* materialization failing a check constraint) was reproduced
**only on the local replay**. CI's live workout checks (`FG-2a/2b`) pass against QA, which suggests
it is replay-specific — **not established**. It is an investigation, not a reason to hold 183.

## 5 · Can a coach reach a `pending` invitee's screen? — **NO; one real defect found instead**

Verified: both doors into `ClientDetailScreen` list **active clients only** —
`coach_dashboard_screen.dart:74` and `:93`, and the compliance roster at
`compliance_service.dart:91-92` (`.eq('status', 'active')`). So 184's refusal does not appear in the
normal flow, and **no screen change is needed for pending invitees.**

**But:** the nutrition-plan sheet's `_save()` (`client_detail_screen.dart:1817-1834`) has **no error
handling**. If the call fails — a network error today, or after 184 a relationship cancelled while
the coach has the screen open — the exception escapes, the sheet keeps spinning and the coach is
told nothing. **Answer:** catch it; on `42501` say *"This client isn't active with you any more"*,
otherwise *"Couldn't save the plan — try again"*; report through the error sink. This should land
with P1, before the batch.

---

## What is now decided, and what still needs the owner

| Item | Status |
|---|---|
| 1 | Decided as a sequence. **Needs the owner once:** the explicit go to run the batch, when P1 and P2 are done. |
| 2 | Decided — wire Welcome. Code change pending. |
| 3 | Decided — `hunger_level` not collected; `compliance_percent` derived. Code change pending. |
| 4 | Decided — 182 approved; 183 approved subject to the read-only substrate check. |
| 5 | Decided — no pending-invitee change; the `_save()` error handling is a code change pending. |

**Unchanged:** `F-21` stays open (`workout_programs` was deliberately not altered); `QAX-SEC-01`,
`QAX-SEC-03`, `QAX-SEC-06` stay open until the batch is applied and verified live; production is
not touched by any of this.
