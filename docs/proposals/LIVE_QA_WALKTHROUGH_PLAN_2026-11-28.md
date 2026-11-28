# Live-QA walkthrough plan (Z4), 2026-11-28: account switch, remediation and failure states

**Status: PREPARED, NOT RUN.** Nothing here may be run until the owner authorizes Z4 with:
- the environment (QA only);
- the named test accounts;
- a time window;
- the journeys allowed;
- whether test data may be created and cleaned up.

**No credentials are written here or anywhere else.** The accounts are the disposable ones that `docs/WEEK1_ACCEPTANCE_WALKTHROUGH.md` already defines: `CoachA`, `CoachB`, `ClientC`, `ClientD`, `Admin` (plus-addressed, created by the owner). This plan adds one more: **`VendorE`** (a vendor), for the vendor-portal checks.

The plan **supplements** that walkthrough (the 14 controlled-beta journeys and the PASS rule) and does not replace it. A beta journey counts only under that document's standard. Nothing in this plan changes the 2/14 / 0/4 counts by itself.

## Build under test
- **Code:** the remediation fixes are on **unmerged** branches. The build is `integration/p0-flutter-stack-rem1` @ `cfbac7c` (CI 7/7 `46122834293`), which contains Cycles 13–15 and RM-1..3.
- **Target:** `flutter run -d chrome --dart-define-from-file=dart_defines/qa.json`, or a phone build by the owner.
- **Recording:** record the commit SHA for each run. Results apply to that build, not to `main`.

## Data created and cleanup
These runs create QA rows: sessions, set logs, workout logs, messages, check-ins, reviews, action items, habit logs, agenda sessions and a class.
- **Cleanup:** only if the owner authorizes it, and only for rows owned by these test accounts.
- **Payments:** none. Stripe stays in test mode or is not reached. No real card is ever entered.

## Scenarios
Columns: **Pre** = preconditions · **Steps** · **Expect** · **Fail if**.

| # | Area (register IDs) | Accounts | Pre | Steps | Expect | Fail if |
|---|---|---|---|---|---|---|
| L1 | Account switch during a workout (FL-62d, RM-3) | ClientC → ClientD, same browser | ClientC has an assigned workout | Start the workout, tick 1 set, start a rest, sign out, sign in as ClientD | ClientD sees no Resume and nothing of ClientC's; ClientC's set is saved once as ClientC | any ClientC data is visible to ClientD; a row is written as ClientD |
| L2 | Finish dialog and back (RM-3; decision S5c) | ClientC | an assigned workout | Finish, then press Android/browser back on the summary, then press Finish again | Points are awarded once and there is one workout log (check Activity/score); a second Finish sends nothing | a second award or log |
| L3 | Slow or failed session start (RM-3) | ClientC | network throttled to "offline" briefly at start | Tick a set while the start fails, then restore the network | The set is saved once, or is visibly not done; it never shows as done without saving | a set shows done but is not in history |
| L4 | Conversation ownership (FL-59c, RM-2) | ClientC, CoachA | the pair is linked | ClientC sends a message, signs out, signs in as ClientD, then opens Messages | ClientD sees none of the ClientC↔CoachA thread; the message shows "Sending…" until stored | ClientD sees any of the thread |
| L5 | Chat with an unknown outcome (U2) | ClientC | — | Go offline mid-send | The message is not shown as sent; the current wording appears (decision U2 pending) | it is shown as sent |
| L6 | Coach actions across a switch (FL-62b, RM-1) | CoachA → CoachB | CoachA has a pending request | Open the Requests card, then switch to CoachB before tapping Accept, then tap | Nothing is accepted for CoachB; nothing is said to CoachB | any acceptance or message for CoachB |
| L7 | Stop coach, paid (FL-62b) | ClientC | test-mode subscription, or skip this row if none | Open Stop coach, then switch accounts before confirming | Nothing is cancelled for the new account | any cancellation for the wrong account |
| L8 | Action Center first-load failure (FL-63d) | ClientC | — | Go offline and open the Action Center, then press Try again online | The failure card with Try again, then the items appear | an empty list or an endless spinner |
| L9 | Notifications unknown (FL-63c; decision U3) | ClientC | — | Go offline and open Home | The bell has no number; the screen reader says "Notifications" | "none unread" or a stale number |
| L10 | Vendor sheet after a switch (FL-63a) | VendorE → CoachA | VendorE has an event | Open New Event, then sign in as CoachA in another tab | The sheet closes; nothing is drawn for CoachA | an empty sheet stays open |
| L11 | Payment outcome (FL-60a, FL-63b) | ClientC | Stripe test mode or none | Start an upgrade and switch accounts before the outcome | Nothing is shown to the new account; no charge | anything shown or charged |
| L12 | Rate your coach and the AI coach screen (FL-62a1) | ClientC → ClientD | ClientC has a coach | Open Rate, type text, then switch accounts | The dialog closes; no review is saved as ClientD | a review is saved as ClientD |
| L13 | Habits (only after Z3/R1-E) | ClientC | 185 and R1-E applied | Log a habit | Logged as ClientC; a log naming another client's habit is refused | the cross-habit log is accepted |
| L14 | Server-side security (only after Z1/Z2 are applied) | ClientD (attacker), ClientC, CoachA | R1-A..D applied | Through the app plus the security suite: re-point a conversation; post into a foreign conversation; edit someone else's message; write a set into someone else's session | Each is refused with 42501; valid sends, mark-read and set saves still work | any refusal missing, or a valid path broken |

## Evidence to record for each run
- the build SHA;
- the environment (QA);
- the browser or device and its OS;
- the account role, never the email;
- the steps;
- expected vs actual;
- a screenshot;
- the time;
- PASS / FAIL / BLOCKED, and whether it reproduces.

A FAIL is filed with repro steps and is not fixed during the run.

## Authorization needed (Z4)
1. Environment: QA only.
2. Accounts: CoachA, CoachB, ClientC, ClientD, VendorE, created by the owner.
3. The window.
4. Which of L1–L14 are allowed. L13 and L14 also need Z3 and Z1/Z2 first.
5. Whether this session may sign in and drive the web build in the in-app browser, or the owner runs it with this sheet.
6. Cleanup: yes or no.
