# Owner decision batch: blocker remediation (2026-11-28)

**For: the 12Circle+ owner (Julia).** None of these is decided here. Each item gives the exact decision, why it matters, the safe options, a **recommendation (not a decision)**, and what it blocks. Where code already ships a behaviour, it is the **safe minimum**: nothing is sent for the wrong account and nothing false is said. Your decision may keep it or change it.

To decide, reply with the item number and option (for example "S1 A, U3 B"). Per the owner-authority rule, I will then record each decision under `docs/MASTER_PRODUCT_DECISIONS.md` §2 with your words before acting on it.

## Part 1: decisions that unblock server work (Item 2)

### S1. PD8 on the server (check-in resubmission after review)
- **Facts:**
  - Your 2026-11-09 decision ("a reviewed weekly check-in counts as done; the client cannot resubmit that reviewed week") is shipped in the app (#45, `20adcc4`).
  - It was never recorded under §2, and the ledger still lists it as open; both records are stale.
  - The server does not enforce it. A direct API call can move a reviewed week back to `submitted` and overwrite the answers the coach replied to (`114_rls_weekly_checkins.sql:84-95`).
  - Migration 151 (B4) audits client answer changes as allowed PHI corrections.
- **Decide:**
  - (1) May I record PD8 under §2 as you worded it?
  - (2) Should the server enforce it?
    - **A**: refuse any change to a reviewed week.
    - **B**: allow resubmission, clear the review fields and notify the coach.
    - **C**: leave it client-only for beta.
  - (3) Do B4 corrections still apply to reviewed weeks?
- **Recommendation:** record PD8; **A**; B4 corrections allowed only before review.
- **Blocks:** C14-MIG-04 (migration).

### S2. Brief #9: self-reported points and challenge progress
- **Facts:** `award_points` credits any positive amount the caller asks for (`035_scoring_engine.sql:78-136`), and challenge progress is client-written.
- **Options:**
  - **A**: accept self-reported scores for the closed beta.
  - **B**: move scoring server-side (triggers derive points from source rows) before beta.
- **Recommendation:** **A** for the closed beta, and **B** before any public leaderboard.
- **Blocks:** C14-MIG-07.

### S3. D-3: atomic availability cancel
- **Facts:** cancelling a coaching call reopens the slot server-side already (187). The coach's cancel and the client notification are separate client steps.
- **Options:**
  - **A**: a `cancel_coaching_call` RPC that cancels and notifies in one transaction.
  - **B**: keep it as is; each step is already owner-checked and recorded.
- **Recommendation:** **B** for beta, **A** later.
- **Blocks:** C14-MIG-06.

### S4. PD-B18: editing your own chat message
- **Facts:** the app has no edit feature. The proposed authorship trigger (R1-C) needs the rule.
- **Options:**
  - **A**: no edits.
  - **B**: the sender may edit within N minutes.
  - **C**: the sender may always edit.
- **Recommendation:** **A** for beta.
- **Blocks:** relaxing R1-C. The strict R1-C does not need this decision.

### S5. Workout behaviour after an account switch and on the finish dialog
- **(a) A dead session's last save.**
  - Fact: if the account goes A→B→A within the 600 ms save window, the abandoned session still saves A's typed set once, as A, to A's session, and charges A's rest overrun once. Nothing ever goes to B.
  - Options:
    - **A**: keep this.
    - **B**: send nothing once A has left, even briefly. This would also stop a Finish A had already pressed.
  - Recommendation: **A**.
- **(b) An unconfirmed value at End or Finish.**
  - Fact: a value typed but not confirmed in the 600 ms before End or Finish is dropped. Before Cycle 14 it went into an orphan session.
  - Options:
    - **A**: drop it, as today.
    - **B**: flush it into the closing session first.
  - Recommendation: **B** if you want no typed value lost. It is a small change.
- **(c) Android back on the finish dialog.**
  - Fact: today the Zone stays on the filed workout after back.
  - Options:
    - **A**: the dialog blocks back.
    - **B**: back leaves the Zone to Home.
  - Recommendation: **B**.
  - RM-3 separately makes a second Finish there unable to award twice, whichever you choose.
- **Blocks:** C14-62d-01 and C14-62d-03.

## Part 2: wording and UX batch (Item 5)

| # | Screen | Question | Options | Recommendation |
|---|---|---|---|---|
| U1 | Chat | New copy **"Sending…"** on a message waiting for the server | keep / reword | Keep |
| U2 | Chat | After a dropped connection the message *may* have been stored, so a resend could duplicate it. Today the screen says "Couldn't send your message — check your connection…" | **A** keep / **B** "Couldn't confirm your message was sent — check the conversation before resending" | **B** |
| U3 | Bells | A failed or unknown unread count looks like zero to a sighted user; only the screen-reader label differs | **A** keep / **B** a small neutral "–" marker / **C** a grey dot | **A** for beta |
| U4 | Bells | A same-account re-count still in flight keeps the last confirmed number | confirm / show nothing until it answers | Confirm |
| U5 | Payments (records only) | A bar still sliding in when the account changed is recorded as "not shown" (over-recording) | confirm / record only bars never started | Confirm |
| U6 | Home coach card | A failed coach read shows no card (now recorded), and the card disappears on each reload | **A** keep / **B** a one-line "Couldn't load your coach" with Try again | **B** (needs a small layout change) |
| U7 | Home coach card | "Rate" is about 33dp tall with no button role | enlarge to 44dp (layout) / Semantics only | Enlarge |
| U8 | Coach dashboard | New "Couldn't load your AI coach signals"; a failed refresh replaces the coach's rows | keep wording + replace / keep the rows with an "out of date" line | Keep the rows + line |
| U9 | Coach dashboard | The "Needs you today" failure has no Try again | add the shared retry / keep | Add |
| U10 | Agenda and Create Class | New "Couldn't add/save/delete the session — …" and "Couldn't create the class — …". The page closes on a switch, including a member's read-only agenda. Delete has no confirmation. B never sees an agenda A opened | approve wording; delete confirmation yes/no; read-only agenda: close / keep (rows are public) | Approve; add delete confirmation; close |
| U11 | Action Center | Now uses the shared "Couldn't load your action items …" + Try again. Should coaches see a client's action-item list (none does today)? | approve; coach list yes/no (density decision pending) | Approve; decide with density |
| U12 | Intake / Stop coach | A→B→A while a step runs and the service refuses part-way: Intake keeps a spinner (base said "Your previous coaching couldn't be ended — end it from Profile.") | **A** silent / **B** the base sentence for A | **B** |
| U13 | Earlier cycles | The Cycle 13 wording and behaviour list in the ledger ("New decisions for Julia (cycle 13)") | review together | — |

## Part 3: authorizations, not product decisions (needed to finish Items 1 and 6)
| # | Authorization | What it unblocks | Recommendation |
|---|---|---|---|
| Z1 | Author and locally replay migrations ≥ 199 for R1-A (conversation participants immutable), R1-B (messages INSERT participant) and R1-C strict (message authorship) | the privacy and security holes in `SECURITY_REMEDIATION_PLAN` | Authorize R1-A now |
| Z2 | R1-D set-log ownership, with a read-only pre-flight count | cross-session set logs | Authorize |
| Z3 | The QA window for 182→186, then R1-E | QAX-SEC-03 (P1 on QA), habit logs | Schedule |
| Z4 | Live-QA walkthrough: sign-ins and normal app writes on QA with named test accounts, in a window you choose. This is the only way to close the device/live evidence gap: there is no iOS simulator (Xcode not installed), no Android AVD and no local backend | beta-journey evidence (2/14, 0/4 unchanged until then) | Authorize, with 2 member + 1 coach + 1 vendor test accounts |
| Z5 | Renew the background-agent sign-in (`claude auth login` / `claude setup-token`) before 2026-12-03 | delegated engineering and review after that date | Renew |
