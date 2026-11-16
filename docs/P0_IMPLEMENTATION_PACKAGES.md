# P0 implementation packages — 12circle-plus controlled beta

How the P0 list maps onto the existing scope (`docs/CONTROLLED_BETA_SCOPE.md`, the ledger) and
onto the specialist team (`.claude/agents/cplus-*`, protocol in `.claude/skills/cplus-team-protocol`).
Nothing from the existing core is dropped: **bookings, session credits and payments stay in scope**
— they are blocked on decisions or external setup, not removed.

Status keys: **DONE-PR** fix ready in an open PR (unmerged) · **READY** decision-free work available
now · **BLOCKED-DEC** Julia's decision · **BLOCKED-MIG** migration apply · **BLOCKED-EXT** external
setup · **MQA** manual QA only.

| # | P0 area | Journeys | Owner | Status | Next package / blocker |
|---|---|---|---|---|---|
| 1 | Authentication & onboarding | 1, 2, 14 | flutter | MQA · BLOCKED-EXT | email provider + hosted URL; then walkthrough 1/2/14. Native deep links (`io.circle12.app`) only if native beta |
| 2 | Coach/client relationships & invitations | 3, 4, 5, 12 | supabase + flutter | BLOCKED-MIG (193/194) · BLOCKED-EXT (email) | after apply: live verification; DEC 3, DEC 4 |
| 3 | Coach & client dashboards | 8, 11 | flutter | DONE-PR (#162, #163) | UX review package (ux-reviewer) of Home + coach dashboard states |
| 4 | Exercise library | 7 | flutter + content | DONE-PR (#166, #168 Edit gating) | content batches (DEC 13, QA writes); name mapping review (`docs/exercise_content/`) |
| 5 | Program creation & assignment | 6 | supabase + flutter | DONE-PR (#161, #169) · BLOCKED-MIG (196–197, 200) | DEC 8 (program sharing) |
| 6 | Workout execution, completion, history | 7, 8 | flutter | verified live (I-WRK-01); units/brief DONE-PR | — |
| 7 | Check-ins & coach review | 9, 10 | flutter | READY for a live leg only with QA-write approval; MQA | DEC 6 (resubmission) |
| 8 | Progress tracking | 11 | flutter | MQA | — |
| 9 | Basic messaging | — | supabase + flutter | BLOCKED-DEC | DEC 2 (which conversations are paid Coach Messaging), DEC 7 (chat times/order) |
| 10 | Settings & notifications | — | flutter + supabase | **READY**: `send-checkin-reminder` must refuse non-service callers (deploy blocker) | push = BLOCKED-EXT/DEC |
| 11 | Secure backend integration | all | supabase + security | DONE-PR (#160, #165, #167, #168) · BLOCKED-MIG/EXT | apply 193–200; deploy functions |
| 12 | **Bookings** | (booking) | supabase + flutter | DONE (screen live, UIX-1); 195 BLOCKED-MIG | — |
| 13 | **Session credits** | (booking) | supabase | 198 DONE-PR; consumption BLOCKED-DEC | DEC 5 / 5b → `book_coaching_session()` package (design in ledger) |
| 14 | **Payments** | 12 (paid) | supabase | BLOCKED-EXT (Stripe test mode) · BLOCKED-DEC 11 | runbook §4 |
| 15 | Coach media privacy | — | supabase + flutter | **READY** (design): move transformation photos to their own public bucket, then make `coach-media` private (DEC 15b path) | needs a migration + data move → apply approval |

## The first packages the team can run now (decision-free, no apply/deploy needed)

1. **`send-checkin-reminder` refuses non-service callers** — `cplus-supabase-engineer`
   (node test + wiring test, CI step), verified by `cplus-qa-verifier`, reviewed by
   `cplus-security-reviewer`. Removes a deployment blocker.
2. **Coach-media privacy path, step 1 (prepared, not applied)** — `cplus-supabase-engineer`
   (migration for a `coach-public` bucket + policies; replay) then `cplus-flutter-engineer`
   (`coach_business_screen` uploads to it; test). Ordered: backend contract first.
3. **UX review of the P1 journeys** — `cplus-ux-reviewer` across journeys 5–12 on `main`,
   findings → small Flutter packages for `cplus-flutter-engineer`.

Each package follows `cplus-team-protocol`: one branch/worktree per owner, contract before
cross-layer work, failing-first tests, independent verification, the report block, no merges.
