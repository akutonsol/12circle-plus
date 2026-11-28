# Coach Copilot — late answers after an account or client switch: remediation proposal

**Status:** proposal only. **Nothing in this document is implemented.** Coach Copilot is held under the
SEC-R3 / Wave 3B-4 blocker, so its behaviour does not change without Julia's ruling.
**Prepared:** cycle 10 (2026-11-23). **Code read at:** `integration/p0-flutter-stack-c9` @ `1b94044`.
**Decision owner:** Julia.

---

## 1 · The finding

The Copilot screen is `apps/mobile/lib/features/coach/presentation/coach_copilot_screen.dart`. Two of
its actions can apply a late answer to the wrong person.

1. **Explain decision**: `_explain`, lines 155–160.
   - It sends the request, waits, then writes the answer into `_explanation`.
   - It doesn't check that the same member is still signed in.
   - It doesn't check that the recommendation on screen is still the one it explained.
2. **Approve & assign**: `_approve`, lines 162–188.
   - It runs three writes in a row: create program, add workout, assign program.
   - It doesn't check between writes that the same member is still signed in.

Cycle 9 (P0-FL-45a, PR #199) changed only the screen's role gate. When a different member is
admitted, `RoleConfirmedLoad.gate(... reset: _resetForMember)` clears the screen's state. It does
not stop the answers still on their way. The P0-FL-45a engineer flagged this, and it was left alone
under the Copilot scope limit.

### What can happen

| # | How | What the member sees or does | Seriousness |
|---|---|---|---|
| L1 | Coach asks to explain client X's recommendation, then selects client Y and generates. X's explanation arrives after Y's recommendation. | Y's recommendation shows **X's** explanation. One client's training rationale is shown as another's. | Wrong facts for the same coach. |
| L2 | Coach A asks to explain, then signs out on the same device. Coach B signs in, opens Copilot and generates. A's explanation arrives. | B sees an explanation of **A's client's** decision, which can mention that client's goals or injuries. | Health context shown across accounts (PHI). |
| L3 | Coach A taps Approve. Between the writes, A signs out and B signs in. | The remaining writes go out with **B's** session, because the database client is shared. Usually the database refuses them, leaving a program created but not assigned, and B sees "Assign failed.". If B is an admin, the writes can succeed: B's session assigns A's program to A's client without B choosing to. On success, B sees "Assigned to ‹A's client's first name› ✓". | A write made under the wrong account, plus a client's name shown across accounts. |
| L4 | Generate (`_run`) and the outlook (`select` → `predictClient`) only drop a late answer when the selected client has changed. If B selects **the same client id** before A's answer arrives (an admin, or a client both coaches share), A's answer is shown to B. | Unlikely, but possible. | Same class as L2. |

Notes:
- **What the server does:** each request carries the token of the member who sent it. The
  explain-decision function and the RPCs therefore authorize the *sender* correctly. These leaks are
  on screen only (L1, L2, L4), apart from L3, where later writes really do use the new member's token.
- **How likely:** it needs a sign-out and a different sign-in on the same device while a Copilot
  request is still running (L2–L4), or quick client switching while explain is slow (L1). It is
  uncommon, but L2 and L3 cross accounts.

---

## 2 · Proposed fix (screen-only, not implemented)

The fix uses only what is already in the tree: `RoleConfirmedLoad.session` and `isCurrent(session)`
from P0-FL-45a, `reportError`, and `isNetworkFailure`.

- **R1 · Drop answers that belong to someone else.** At the start of `_explain`, `_approve`, `_run`
  and the client `select`, capture `final s = _member.session;`. After every `await`, stop if
  `!_member.isCurrent(s)`: change no state and show nothing. In addition:
  - `_explain` also stops unless `_rec?['trace_id'] == tid`, which fixes L1.
  - `_run` and `select` keep their existing client-id check, which together with R1 fixes L4.
- **R2 · Stop an approval when the account changes mid-way.** Capture
  `final uid = currentUser.id` before the first write. Before each later write, check the same member
  is still signed in. If not:
  - stop the chain and send no further writes;
  - record it with `reportError('CoachCopilotScreen.approve', StateError('account changed during
    assign'))`;
  - show nothing on the new member's screen.

  The program already created stays as it is today when a later step fails. Cleaning it up is a
  separate question (§4).
- **R3 · Honest failure wording**, which the error contract asks for anyway:
  - "Assign failed." becomes "Couldn't assign the session — ‹next step›", recorded with
    `reportError`.
  - "Explanation unavailable (deploy explain-decision)." becomes "Couldn't load the explanation —
    ‹next step›" with a 44px retry.

**What R1–R3 deliberately leave alone:**
- `predictClient`, `evaluateWeek`, `regenerateProgram` and their swallows. These are the SEC-R3 sites
  pinned by coordinator §15.
- The `reportFailure` sink, which stays unwired.
- How a recommendation is generated or chosen.
- Any RPC, edge function, policy or migration.

The predicted outlook would still show no card when it fails, which is the same blocker as today.

**Tests that would come with it** (the cycle 9 identity matrix):
- account switch A→B with explain, generate, outlook and approve each in flight;
- the previous member's late answer arriving after the switch (dropped);
- a client switch with a late explanation (dropped);
- the same client id selected by B (dropped);
- an approval interrupted between each pair of writes (no further write, recorded, nothing shown);
- sign-out with nobody signing in;
- each failure path showing the contract wording with a working 44px retry.

Mutants:
- remove each `isCurrent` check;
- remove the `uid` re-check;
- remove the trace-id check.

**Estimated size:** one screen file plus one test file, within the same review, mutation and CI
process as cycles 6–9.

---

## 3 · Options for Julia

| Option | What it means | Recommendation |
|---|---|---|
| **A** | Approve R1–R3 now as a screen-only change. SEC-R3's three functions and coordinator §15 stay as they are; 3B-4 still owns the service-layer swallows. | **Recommended.** It removes the cross-account display (L2, L4) and the wrong-account write (L3) without touching the blocked generation paths. |
| B | Approve R1 and R2 only. Keep the current failure wording until 3B-4. | Acceptable if you want the smallest possible change. |
| C | Wait for Wave 3B-4 and fix everything together. | L2 and L3 stay possible until then. |

---

## 4 · Related questions (open, not decided here)

- **Q1 · Partly created programs.** When an approval stops after "create program", should the empty
  program be left (today's behaviour on any failed step) or removed? Removing it is a new delete
  path and a product rule.
- **Q2 · Telling the coach who left.** Should coach A learn that their approval stopped half-way?
  Nothing in the app can tell A after they sign out. This is a product question, possibly
  answered with a server-side record.

Until Julia rules on §3 and §4 this is read-only: no Copilot code changes in cycle 10.
