# Cycle 13 identity inventory (P0-FL-59) — closure map

The two inventories (Area A state holders, ids A-xx; Area B write sites, ids W/E/S) were taken read-only at base `a82f993`, before any fix. Classes: **1** = data exposure, **2** = wrong-user write, **3** = stale local state. Status values: CLOSED (a package report names the id as fixed), PARTLY (part fixed; the note says what remains), OPEN-ENG, OPEN-DECISION (Julia), OPEN-MIGRATION, OUT-OF-SCOPE (SEC-R3, Women's Health, `home_screen.dart:817`). Rows marked NOT MAPPED are explained in section 3. All evidence is automated (unit and widget tests, mutants, reviews). There is no device, two-tab web, or live-QA evidence. Package → PR at final head: FL-59a #228 `2e74c54`, FL-59b #227 `5bafd65`, FL-59c #222 `0335ee6`, FL-59d #221 `d3dc7ea`, FL-59e #225 `cc46fe1`, FL-59f #224 `ffc4b32`, FL-60a #226 `491c286`, FL-60b #219 `97c3de1`, FL-60c #220 `2a8e471`, FL-61 #223 `b083f35`; combined on `integration/p0-flutter-stack-c13` @ `a446926`. The source inventories and engineer reports were working files of the cycle and are not kept in the repository; each PR description summarises its package's closures.

## 2. Closure tables

### Class 2 — wrong-user write

| ID | Short description | Severity (inventory) | Status | Closed by | Note |
|---|---|---|---|---|---|
| A-01 | Workout Zone writes A's sets, log and points as B | HIGH | CLOSED | FL-59b | Server check on set-log session ownership still needs a migration. |
| A-02 | Selected workout never cleared; B starts A's program | HIGH web / MED mobile | CLOSED | FL-59b | |
| A-03 | Active workout keeps A's sets for B | MED | CLOSED | FL-59b | |
| A-04 | Rest timer keeps A's countdown; penalties charged to B | HIGH | CLOSED | FL-59b | Julia decides whether a running rest timer survives re-authentication. |
| A-05 | Selected conversation kept; B writes into A's thread | HIGH | CLOSED | FL-59c, FL-59f | Messages INSERT participant check (QAX-SEC-04) still needs a migration. |
| A-06 | Password reset not tied to the recovering account | HIGH impact, low likelihood | CLOSED | FL-59a | Refused-reset and expired-link wording waits on Julia. |
| A-08 | Workout feedback dialog submits as B | MED | CLOSED | FL-59b | |
| A-09 | Resume banner offers A's session to B | MED | CLOSED | FL-59b | Follow-up: banner still hides itself when its lookup fails. |
| A-10 | A's program shown as B's Today or Directory card | MED | CLOSED | FL-59b, FL-60b | Follow-up: Home and Directory give no feedback when a start is refused. |
| A-11 | Coaching-mode plan RPC runs as B | HIGH impact, low likelihood | CLOSED | FL-59e | Gap between client check and token stays server-side (migration class). |
| A-12 | Coach review draft sent as B | MED | CLOSED | FL-59c | PD8 refusal rule and its wording wait on Julia. |
| A-14 | Awards after an await go to whoever is signed in | MED | PARTLY | FL-59e, FL-59b, FL-59c | `live_challenge_service` awards not named by any report; server-side gap remains. |
| A-15 | Rate-your-coach review saved under B | MED | CLOSED (C14) | FL-62a1 (#231) | Owner captured at open; checked before/after the upsert; card reads the signed-in member's coach only. Error-card half: a failed read is now recorded, but showing it needs a layout decision (C14-62a1-01). |
| A-16 | Late restore or bind writes A's workout into B's state | LOW | CLOSED | FL-59b | |
| W1 | Intake writes A's health answers into B's profile | HIGH P1 | CLOSED | FL-59e | Intake "Nothing was lost" wording waits on Julia. |
| W2 | Reset form changes B's password | HIGH P1 | CLOSED | FL-59a | |
| W3 | Chat send inserts into A's conversation as B | HIGH P1 | CLOSED | FL-59c | QAX-SEC-04 migration still open. |
| W4 | Set tap files A-session set log as B | HIGH P1 | CLOSED | FL-59b | Set-log ownership migration still open. |
| W5 | Finish logs A's workout for B; 0-row completion counted | HIGH P1 | CLOSED | FL-59b | |
| W6 | Weekly check-in upserts A's answers over B's week | HIGH P1 | CLOSED | FL-59c | |
| W7 | A's weight or measurement saved to B | HIGH P1 | CLOSED | FL-59e | |
| W8 | Coach A's price saved onto coach B | HIGH P1 | CLOSED | FL-59d | |
| W9 | Focus sheet overwrites B's exercise media | HIGH P1 | CLOSED | FL-59d | |
| W10 | B's voice overlay points at A's recording | MED P2 | CLOSED | FL-59d | Julia decides on release during the microphone permission prompt (D-2). |
| W11 | Coaching-mode sheet applies A's choice to B | MED P2 | CLOSED | FL-59e | |
| W12 | Cancel-coach dialog ends B's coaching | MED P2 | NOT MAPPED | — | See section 3. |
| W13 | A's rating becomes B's public review | MED P2 | CLOSED (C14) | FL-62a1 (#231) | Upsert stamped with the owner captured at open; nothing sent for B. |
| W14 | Coach note stored as B's | MED P1 | CLOSED | FL-59f | |
| W15 | AI coach draft, memory or persona saved for B | MED P2 | CLOSED (C14) | FL-62a1 (#231) | `AICoachService(owner:)`; persona/memory writes refuse and record for anyone else; Add memory dialog owned. |
| W16 | Scan result or selected food logged by B | MED P2 | CLOSED | FL-59e, FL-61 | FL-61 closes it only when merged with or after FL-59e. |
| W17 | Video response sent by B | MED P2 | CLOSED | FL-59d | |
| W18 | Review feedback saved as B's review | MED P2 | CLOSED | FL-59c | |
| W19 | Client-page sheets and price saved by B | MED P2 | CLOSED | FL-59f | Action Center layout unchanged; density decision with Julia. |
| W20 | Assign program/habits leaves client with none after a switch | MED P2 | OPEN-MIGRATION | — | Needs one atomic RPC; `coach_program_service` is SEC-R3 protected. |
| W21 | Create/edit exercise steps run as B | MED P2 | CLOSED | FL-59d | Julia owns the exercise detail AI content path (R3-3). |
| W22 | A's typed program, class, slot, invite or event created as B | MED P2 | PARTLY | FL-59d, FL-59f, FL-59a, FL-62a2 (#230) | `create_class_screen` closed in Cycle 14 (FL-62a2). `sendInvite` email step still multi-step. |
| W23 | A's draft post or comment published as B | MED P2 | NOT MAPPED | — | See section 3. |
| W24 | Score awards after awaits land on B | MED P2 | CLOSED | FL-59e, FL-59b, FL-59c | Award RPCs use `auth.uid()`; final gap is server-side. |
| W25 | Workout feedback inserted with A's session as B | MED P2 | CLOSED | FL-59b | |
| W26 | A's plan change creates checkout for B | LOW P2 | CLOSED | FL-60a | |
| W27 | Empty B-to-A's-coach conversation created | LOW P2 | CLOSED | FL-59c | |
| W28 | A's typed goal or habit saved to B | LOW P2 | PARTLY | FL-60c | Goals named fixed. FL-59e describes an owner on the habit add sheet but never names W28. |
| W29 | Integrations toggle writes B's row from A's state | LOW P2 | CLOSED | FL-59d | OAuth marked connected on page open waits on Julia (D-1). |
| W30 | Intake coach pick links B | LOW P2 | CLOSED | FL-59e | |
| W31 | Booking from A's coach list as B | LOW P2 | CLOSED | FL-59e | |
| W32 | Second-step notifications sent by B | LOW P2 | NOT MAPPED | — | See section 3. |

### Class 1 — data exposure

| ID | Short description | Severity (inventory) | Status | Closed by | Note |
|---|---|---|---|---|---|
| A-07 | Coach dashboard roster, check-ins, bell kept for B | HIGH | CLOSED | FL-59f | |
| A-13 | Coach check-in queue and selection not keyed by user | HIGH | CLOSED | FL-59c | |
| A-17 | Client page providers keyed by client only | HIGH | CLOSED | FL-59f | Round 1 left the header name to FL-59a's AccountScope. |
| A-18 | Coach workout stats families show A's clients | MED | CLOSED | FL-59b | |
| A-19 | Coach revenue, payouts and tier held for B | MED | CLOSED | FL-60a | |
| A-20 | Health and score values held via `valueOrNull` | MED | PARTLY | FL-60b | Streak named; Activity and nutrition cards fixed. Home, score and AI insights not reported. |
| A-21 | A's plan or coach held; gate opens on A's plan | MED | CLOSED | FL-60a | Directory coach banner left; FL-60b judged it shows nothing of A's. |
| A-22 | Habit reminders outlive the account | MED | CLOSED | FL-59a | Reminders with no owner wait on Julia. |
| A-23 | Vendor attendees and program builder held for B | MED vendor / LOW builder | CLOSED | FL-59f, FL-59a | Vendor half moved from FL-59f to FL-59a in round 5. |
| A-24 | Selected class shows A's meeting link to B | LOW | CLOSED | FL-59f | |
| A-25 | Teasers, check-in history, class and What's-on rows held | LOW | PARTLY | FL-59c | Teasers and check-in history done. Class, What's-on and workout-list rows not named as A-25. |
| A-26 | Selected exercise detail shows coach A's private exercise | LOW | CLOSED | FL-59d | Route `extra` still carries A's exercise while the screen stays mounted. |
| A-27 | Coach adjustment brief kept for B | LOW | CLOSED | FL-59b | |
| E1 | Client detail shows A's client PAR-Q, photos | HIGH P1 | CLOSED | FL-59f | |
| E2 | Check-in queue shows A's clients' notes | HIGH P1 | CLOSED | FL-59c | |
| E3 | Progress keeps A's body photos and weights | HIGH P1 | CLOSED | FL-59e | |
| E4 | Intake shows A's health answers and photos | HIGH P1 | CLOSED | FL-59e | |
| E5 | Chat thread, photos and draft stay for B | HIGH P1 | CLOSED | FL-59c | Julia confirms a dropped chat stays closed. |
| E6 | AI coach screen keeps A's conversation and memories | HIGH P1 | CLOSED (C14) | FL-62a1 (#231) | Screen keyed by uid; every await re-checks the owner; late chat/insight/generate answers never drawn for B. |
| E7 | Coach client workout screen shows A's stats | MED P1 | CLOSED | FL-59b | |
| E8 | Availability shows A's client names and times | MED P1 | CLOSED | FL-59d | Partial cancel needs an atomic RPC (D-3, Julia). |
| E9 | Check-in and booking screens keep A's appointments | MED P2 | CLOSED | FL-59c, FL-59e | |
| E10 | Workout, sets and timer shown to B as authoritative | MED P2 | CLOSED | FL-59b | |
| E11 | Selected conversation persists; direct `/chat` opens A's | MED P2 | CLOSED | FL-59c | |
| E12 | Event ticket QR of A shown to B | MED P2 | CLOSED | FL-60c | Ticket wording decisions wait on Julia. |
| E13 | A's Stripe portal, onboarding or checkout opens for B | MED P2 | PARTLY | FL-60a | Event-ticket checkout not yet tied to its owner (FL-60a and FL-60c follow-ups). |
| E14 | Open sheets show A's prefilled values | MED P2 | NOT MAPPED | — | See section 3. |
| E15 | Habit reminders keep firing after sign-out | LOW P2 | CLOSED | FL-59a | |
| E16 | Pods and integrations show A's data | LOW P2 | CLOSED | FL-59d, FL-60c | |
| E17 | Cross-check bundle of providers with no user watch | LOW | NOT MAPPED | — | See section 3. |

### Class 3 — stale local state

| ID | Short description | Severity (inventory) | Status | Closed by | Note |
|---|---|---|---|---|---|
| A-28 | Router ignores uid change and remote sign-out | MED | CLOSED | FL-59a | Expired-session wording waits on Julia. A hidden tab drops A's state only on its next frame. |
| A-29 | Redirect role read not re-checked after await | LOW | CLOSED | FL-59a | |
| A-30 | Pending invite token deleted when B signs in | LOW | OPEN-DECISION | — | Recorded unchanged by FL-59a; keep or bind the token is Julia's call. |
| A-31 | Notification watcher keeps A's subscription | LOW | CLOSED | FL-59a | |
| A-32 | Program adherence provider ignores the user | LOW | CLOSED | FL-59b | |
| A-33 | Notifier writes after dispose | LOW | NOT MAPPED | — | See section 3. |
| A-34 | Admin searches and screen counters carry over | LOW | CLOSED | FL-59f | Water counters are keyed per member in FL-59e and FL-60b. |
| A-35 | Whole-`User` watches reset the same member's state | LOW | CLOSED | FL-59c, FL-60b | |
| S1 | Router never re-routes on A-to-B or session loss | MED P2 | NOT MAPPED | — | See section 3. |
| S2 | Pending invite token deleted on 42501 | LOW | OPEN-DECISION | — | Same finding as A-30; PendingInvite was left unchanged on purpose. |
| S3 | Notification watcher re-subscribes only on build | LOW | CLOSED | FL-59a | |
| S4 | Failed toggle save reverts B's displayed toggle | LOW | OPEN-ENG | — | No report names it or touches `notification_preferences_screen`. |
| S5 | Week status and streak reads may mix users | LOW | CLOSED | FL-59c | |
| S6 | Zero-row goal or action-item update reported as success | LOW | CLOSED | FL-59e, FL-60c | |
| S7 | Post-await `state=` on disposed notifiers | LOW | CLOSED | FL-59e | |
| S8 | Ticket `setState` in finally without `mounted` | LOW | CLOSED | FL-60c | |
| S9 | Sample-data providers with no personal data | LOW | NOT MAPPED | — | See section 3. |

## 3. Not mapped

- **A-15 / W13 (Rate your coach):** *(Closed in Cycle 14 by FL-62a1, #231 — see section 5.)* FL-59a's containment tests open this dialog under AccountScope. No report names either id or adds an owner check at save. The error-card half of A-15 is not reported at all.
- **W12 (cancel coach):** FL-59d added `expectedUid` to `cancelCoach`. FL-59a guarded the profile dialog and FL-60a guarded Stop coach. No report names W12, and PR FL-59d still lists callers that do not pass `expectedUid`.
- **W15 / E6 (AI coach screen):** *(Closed in Cycle 14 by FL-62a1, #231 — see section 5.)* this screen appears only in FL-59a's containment brief. No package owned `ai_coach_screen`, and no report names either id.
- **W23 (posts and comments):** FL-59e round 2 says the post sheet and comment box now have an owner. It never names W23.
- **W32 (second-step notifications):** parts are re-checked in FL-59c (review feedback), FL-59d (availability cancel) and FL-59e (comments). FL-59f lists accept/decline notifications as still open. No report names W32.
- **E14 (prefilled sheets):** the inventory says to fix this "with each write fix". No report names E14, and W23 is itself unmapped.
- **E17 (provider bundle):** most members are fixed under other ids (A-27, A-32, A-17, A-23). `coachLeaderboardProvider` was deliberately left (FL-59f). No report mentions `recentUsersProvider`, `platformStatsProvider` or `_sessionLogsProvider`.
- **A-33 (writes after dispose):** FL-59e names S7 and the A-11 `mounted` guards, which cover the same two files. It never names A-33.
- **S1 (router):** this is the same defect as A-28, which FL-59a closed. No report names S1, and the inventory filed it as a design choice.
- **S9 (sample data):** the inventory records no defect and no fix, so there is nothing to close.

## 4. Counts per status per class

| Class | CLOSED | PARTLY | OPEN-ENG | OPEN-DECISION | OPEN-MIGRATION | OUT-OF-SCOPE | NOT MAPPED | Total |
|---|---|---|---|---|---|---|---|---|
| 2 wrong-user write | 39 | 3 | 0 | 0 | 1 | 0 | 3 | 46 |
| 1 data exposure | 25 | 3 | 0 | 0 | 0 | 0 | 2 | 30 |
| 3 stale state | 11 | 0 | 1 | 2 | 0 | 0 | 3 | 17 |
| **All** | **75** | **6** | **1** | **2** | **1** | **0** | **8** | **93** |

Migration items still open outside these rows: the QAX-SEC-04 messages participant check (A-05, W3), set-log session ownership (A-01, W4), and the server-side `auth.uid()` award gap (A-11, A-14, W24).

## 5. Cycle 14 update (2026-11-27)

Counts in section 4 now include Cycle 14. Changed rows: **A-15, W13, W15, E6** (NOT MAPPED → CLOSED, FL-62a1 #231); **W22** stays PARTLY (Create Class closed by FL-62a2 #230; `sendInvite` remains). Cycle 14 also closed items that had no inventory ID of their own:
- **Manage Agenda** (`event_agenda_screen.dart`, the FL-59a follow-up): bound to its account, 0-row writes are failures (FL-62a2 #230). Its callers do not yet pass `owner:` (C14-62a2-02, Cycle 15 FL-63a).
- **`cancelCoach` callers and dashboard approve/decline** pass `expectedUid` (FL-62b #229). A wrong-account write was **not** reachable on the base; this is defence in depth plus single recording.
- **AI COACH SIGNALS and NEEDS YOU TODAY cards** draw only rows owned by the signed-in coach; coach action-item families carry an owner tag (latent) (FL-62c #233).
- **Account switch over an open workout** has a combined test; it found and fixed two workout defects (FL-62d #232).
Still NOT MAPPED after Cycle 14: W32, E14, E17, A-33 (unchanged; not in Cycle 14 scope). Migration-class items are documented in `docs/MIGRATION_CLASS_IDENTITY_RISKS_C14.md` (C14-MIG-01..07); none was applied.

## 6. Cycle 15 update (2026-11-28)

No inventory row changed status in Cycle 15 (FL-63 was honesty and test hygiene). Two identity-adjacent follow-ups closed:
- Manage Agenda now receives the portal's captured owner (C14-62a2-02, FL-63a #237).
- A vendor editor sheet first built after a switch closes itself and records the stop once (FL-59a follow-up, FL-63a #237).

Counts in section 4 are unchanged from the Cycle 14 update.
