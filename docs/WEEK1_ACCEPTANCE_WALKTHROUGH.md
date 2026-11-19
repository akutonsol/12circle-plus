# Week-one acceptance walkthrough — the 14 controlled-beta journeys

Run on **QA only**, by a person (Julia or a delegate) with disposable test accounts they create
themselves. No real customer data, no real payments. Companion to
`docs/CONTROLLED_BETA_SCOPE.md` (what each journey depends on) and
`docs/BETA_WEEK1_MANUAL_WALKTHROUGH.md` (the detailed program → workout → coach-view route,
journeys 6–8).

**Run order and readiness.** "Ready" = runnable on QA as it is today. Most journeys need the
approvals in `docs/BETA_RELEASE_RUNBOOK.md` first.

| # | Journey | Priority | Ready on QA today? | Needs first |
|---|---|---|---|---|
| 1 | Client signup | **P1** | partly — no email provider, so confirmation mail is not sent | email provider + hosted URL |
| 2 | Coach signup | P2 | partly — no email provider | email provider + hosted URL |
| 3 | Coach invitation | **P1** | no | `send-invite-email` deployed, email, `APP_URL` |
| 4 | Client acceptance | **P1** | no | migration 194 |
| 5 | Relationship activation | **P1** | yes (pre-193 rules) — rerun after 193 | migration 193 for decision 1 |
| 6 | Program assignment | **P1** | yes — rerun after 196–197 | migrations 196–197 for ownership checks |
| 7 | Workout execution | **P1** | yes | — |
| 8 | Workout completion | **P1** | yes | — |
| 9 | Check-in submission | **P1** | yes | — |
| 10 | Coach check-in review | **P1** | yes | — |
| 11 | Client progress visibility | P2 | yes | — |
| 12 | Relationship termination | **P1** | unpaid path yes; paid path no | Stripe test mode + billing functions |
| 13 | Access revocation | **P1** | partly | migrations 193/195, #160 deployed |
| 14 | Account recovery | P2 | no | email provider + hosted URL |

**Accounts** (create once, record in the evidence sheet, never reuse real people):
`CoachA` (coach), `CoachB` (coach), `ClientC` (client), `ClientD` (client), and an existing
`Admin` for spot checks. Use plus-addressed emails on a mailbox you control.

**Evidence for every journey:** screenshot of the expected screen; the time; the account; for
authorization checks, the exact refusal text. Mark **PASS** only when every expected result holds
and every authorization check refuses as stated.

---

## 1. Client signup — P1
- **Start:** signed out. **Preconditions:** hosted QA URL; email provider configured.
- **Steps:** `/signup` → name, email, password → submit → open the confirmation email → follow the
  link → sign in → complete intake.
- **Expected:** "Account created — check your email to confirm it, then sign in" (no session
  before confirming); after confirming, sign-in lands in intake; intake completes once and does
  not repeat at the next sign-in; role is **client**.
- **Authorization checks:** sign-up may request only `client`, `coach` or `vendor` (`handle_new_user`); a request for `admin`, `content_manager` or another staff role becomes `client`.
- **Failure cases:** sign-in before confirming → refused with a clear message; reused email →
  error, no second account.
- **Evidence:** confirmation email (sender domain), Home after intake, profile role.
- **Pass:** all of the above.

## 2. Coach signup — P2
- **Start:** signed out. **Preconditions:** email provider + hosted URL.
- **Steps:** `/signup` choosing **coach** → confirm email → sign in → complete the coach profile.
- **Expected:** lands on `/coach-dashboard`; an empty roster says "no clients", not an error;
  profile role is `coach`.
- **Authorization checks:** a client account sees no other coach's roster data; staff roles
  cannot be chosen at sign-up (see 1).
- **Evidence:** dashboard; profile role. **Pass:** a coach account works end to end with no admin step.

## 3. Coach invitation — P1
- **Start:** `CoachA`. **Preconditions:** `send-invite-email` deployed, email provider, `APP_URL`.
- **Steps:** coach dashboard → invite → enter `ClientD`'s email → send.
- **Expected:** "invite sent" only when it was sent; the email arrives; its link is
  `<APP_URL>/#/signup?invite=<token>` on the **QA** host (not `12circle.app`).
- **Authorization checks:** a client cannot send invites.
- **Failure cases:** email provider down → the screen says it failed (no false success).
- **Evidence:** the email and its link host. **Pass:** link host = hosted QA URL.

## 4. Client acceptance — P1
- **Start:** `ClientD`, signed out. **Preconditions:** migration 194; journey 3 done.
- **Steps:** open the invite link → sign up (or sign in) with **the invited email** → confirm →
  sign in.
- **Expected:** on sign-in the invite is redeemed; `CoachA` appears as ClientD's coach; CoachA
  sees ClientD on the roster; both get a notification; the invite cannot be used again.
- **Authorization checks:** the same link with a **different** email account → refused
  ("invite not valid"); an expired or used invite → refused, same message.
- **Evidence:** roster, notifications, refusal text. **Pass:** one link, one relationship, others refused.

## 5. Relationship activation — P1
- **Start:** `ClientC`. **Preconditions:** for decision 1, migration 193.
- **Steps:** marketplace / intake → request `CoachA` → `CoachA` approves.
- **Expected:** after approval ClientC sees CoachA live (no restart); coaching features unlock.
- **Authorization checks (after 193):** a relationship ClientC **activates itself** gives data
  sharing only — Messages/Bookings stay behind the paywall.
- **Failure cases:** coach declines → client told; request again possible.
- **Evidence:** before/after screens, paywall. **Pass:** approval unlocks; self-activation does not.

## 6. Program assignment — P1
- **Start:** `CoachA`. **Preconditions:** ClientC is CoachA's client; follow
  `BETA_WEEK1_MANUAL_WALKTHROUGH.md` steps 1–5.
- **Expected:** the program with a day for today appears on ClientC's Home and Workouts without a
  restart; ClientC gets a notification.
- **Authorization checks (after 196–197):** CoachA's assign sheet lists only CoachA's programs;
  CoachB cannot assign to ClientC (no relationship).
- **Evidence:** client Home Today card. **Pass:** program visible live to the right client only.

## 7. Workout execution — P1
- **Start:** `ClientC`. **Steps:** Home → Begin session → log sets (lb by default, kg if the
  profile is metric) → each exercise's info shows form/steps where the library covers it.
- **Expected:** loads read in the member's unit (e.g. "135 lb", never "61.23496995kg"); the resume
  banner appears only for a session left in progress.
- **Evidence:** a logged set; the unit. **Pass:** units correct; no stray kg.

## 8. Workout completion — P1
- **Steps:** finish the session.
- **Expected:** summary; history shows it under today's local date; CoachA's open dashboard shows
  the completion **without reopening** (#163); a PR appears only from confirmed sets.
- **Evidence:** history entry; coach dashboard. **Pass:** both sides agree.

## 9. Check-in submission — P1
- **Start:** `ClientC`. **Steps:** `/checkins` → fill the weekly check-in → submit.
- **Expected:** "submitted" only when saved; CoachA's queue and open dashboard show it live.
- **Failure cases:** offline → a failure message, the form keeps its values.
- **Evidence:** client confirmation; coach queue. **Pass:** coach sees it within seconds.

## 10. Coach check-in review — P1
- **Start:** `CoachA`. **Steps:** `/coach-checkin-review` → open ClientC's check-in → feedback →
  submit.
- **Expected:** "Feedback submitted" only when saved; ClientC gets "Coach Feedback Ready" and sees
  the feedback on the check-in.
- **Authorization checks:** CoachB cannot review ClientC's check-in (0-row update reported as a
  failure, not success).
- **Open decision:** resubmitting after a review (DEC 6) — record what happens, do not judge it.
- **Evidence:** client view of the feedback. **Pass:** review visible to the client only.

## 11. Client progress visibility — P2
- **Steps:** ClientC → Progress, Workout history, Strength progression; CoachA → client detail.
- **Expected:** latest first, local dates, member's units; CoachA sees ClientC's progress, CoachB
  does not. **Pass:** both views consistent; no cross-coach visibility.

## 12. Relationship termination — P1
- **Start:** `ClientC`. **Steps (unpaid):** Profile → Cancel Coach → reason → confirm.
- **Expected:** the coach card clears; **coaching features lock immediately** (#162);
  CoachA is notified; ClientC's program history stays visible to ClientC.
- **Paid path (after Stripe test mode):** a paid coaching subscription is set to cancel at period
  end; coaching continues until then (decision 2).
- **Authorization checks (after 200):** if ClientC then joins CoachB, CoachB cannot read CoachA's
  programs; ClientC still can.
- **Evidence:** before/after paywall; notification. **Pass:** lock is immediate; history kept.

## 13. Correct access revocation — P1
- **Preconditions:** migrations 193 and 195; #160 deployed.
- **Checks:** after termination, `/messages`, `/appointments`, `/action-items` show the paywall;
  booking a call with CoachA is refused by the server; the AI Coach screen is refused for a
  Free/Self-Guided account (and its function returns `plan_required`).
- **Pass:** every gated feature refuses, server-side included.

## 14. Account recovery and re-entry — P2
- **Preconditions:** email provider; hosted URL in Supabase Auth redirect list.
- **Steps:** `/forgot-password` → email → link → new password → sign in.
- **Expected:** the link opens the hosted app in recovery mode; the new password works; the old
  one does not.
- **Failure cases:** an expired link → a clear message. **Pass:** recovery completes on the web.

## Record the result
For each journey: PASS / FAIL / BLOCKED (with the blocker), the evidence links, and the build
(commit SHA) tested. A FAIL is filed with steps to reproduce; it is not fixed during the run.
