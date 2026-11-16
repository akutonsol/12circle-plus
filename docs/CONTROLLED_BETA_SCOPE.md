# Controlled coaching beta — minimum journeys

A controlled beta is **a few invited coaches and their clients**, on QA-grade infrastructure,
with payments either off or in Stripe test mode. It is beta-ready only when every journey
below has **integration evidence** (local replay, live QA suite, or a recorded manual run) and
its authorization rule is enforced in the database, not only in the UI. Status as of
2026-11-16; "PR" = open, unmerged.

| # | Journey | Screens | Server / API | Tables | Authorization rule (DB) | Integration evidence required | Status |
|---|---|---|---|---|---|---|---|
| 1 | Client signup | `/signup` → confirm email → `/login` | Supabase Auth | `auth.users`, `user_profiles` (trigger) | role defaults to client; no self-escalation (d02) | live: new account → profile row, role client | **gap**: CI uses pre-made fixtures; email provider not configured |
| 2 | Coach signup | `/signup` (coach) → `/coach-dashboard` | Auth + profile | `user_profiles` (role coach) | who may become a coach is server-controlled (d02) | live: coach account reaches dashboard | **gap**: no live leg; coach role assignment path to confirm |
| 3 | Coach invitation | coach dashboard → invite | `send-invite-email` | `coach_invites` | coach manages own invites | live: invite row + email sent (test inbox) | **blocked**: function not deployed; no email provider |
| 4 | Client acceptance | `/signup?invite=` → sign-in | `accept_coach_invite(token)` (194) | `coach_invites`, `coach_client_relationships` | verified email, unexpired, single use; one refusal | replay ✓ (`policy_193_194` 21/21); live after apply | **migration**: 194 pending |
| 5 | Relationship activation | request → coach approves | PostgREST | `coach_client_relationships` | `activated_by` (193): client self-activation = data sharing only | replay ✓; live after apply | **migration**: 193 pending |
| 6 | Program assignment | coach client detail → Assign | `assignProgram` | `workout_program_assignments`, `workout_programs`, `program_workouts` | coach: active relationship (185) + own program (197); client: own programs only (196) | replay ✓ (`assignment_196_replay` 10/10, ownership matrix) | **migration**: 196–197 (PR #161), 185 (gated) |
| 7 | Workout execution | `/train` → `/workout-detail` → `/active-workout` | session store | `workout_sessions`, `workout_set_logs` | own rows only | **live ✓ I-WRK-01** every CI run | form/steps for assigned movements → PR #166 |
| 8 | Workout completion | finish → summary | session store; PR trigger (190) | `workout_sessions`, PRs, `score_events` | own rows; PR from confirmed sets only | **live ✓** (I-WRK-01) | coach view live → PR #163 |
| 9 | Check-in submission | `/checkins` → `/checkin-form` | PostgREST | `weekly_checkins`, `notifications` | own rows | unit ✓; live leg **missing** | **gap**: add a live leg |
| 10 | Coach check-in review | `/coach-checkin-review` | `submitCoachFeedback` | `weekly_checkins` | active coach only (0-row update = refused) | unit ✓; live **missing** | **gap**; resubmission after review = DEC 6 |
| 11 | Client progress visibility | `/progress`, `/workout-history`, `/strength-progression` | PostgREST | sessions, set logs, measurements | own rows; coach reads active clients | unit ✓ (units #157/#158) | manual QA |
| 12 | Relationship termination | Profile → Cancel Coach; Settings | `cancelCoach`, `cancel-subscription` | relationships, `subscriptions` | decision 2: paid coaching ends at period end | unit ✓ (#149); refresh → PR #162 | **blocked** for paid path: functions not deployed |
| 13 | Correct access revocation | paywalled screens | `client_plan()` | relationships, subscriptions | ended coaching → plan drops; server refuses bookings (195), AI (PR #160) | replay ✓ (193/195); node ✓ (#160) | **migration** 193/195 + **deploy** #160 |
| 14 | Account recovery & re-entry | `/forgot-password` → email → `/reset-password` | Auth recovery | `auth.users` | Supabase Auth | live: reset email → new password works | **blocked**: email provider; native deep links absent (web only) |

## Essential for the controlled beta

Journeys 1–14 above; coach dashboard and client Home; in-app notifications; messaging between a
coach and their clients (enforcement scope = DEC 2); booking a call with the coach (195).

## Later, for public launch

Payments live (Stripe production), marketplace and coach discovery, public leaderboards and
challenges with prizes (needs server-side scoring), AI coaching at scale (cost caps, PD-A13/14),
classes and events, vendor portal, push notifications, native app-store distribution, full
exercise media, women's-health module (out of this programme's scope).

## What "beta-ready" requires (none is met yet)

1. Journeys 1–14 each have integration evidence (live leg or recorded manual run).
2. Migrations 193–198 applied to QA, with the live suites green after.
3. Edge Functions deployed from `main`; email provider and `APP_URL` set; vault set.
4. Julia's week-1 walkthrough recorded.
