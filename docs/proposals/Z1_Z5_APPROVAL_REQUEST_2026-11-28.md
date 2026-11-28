# Z1–Z5: status and one approval request (2026-11-28)

**For: the 12Circle+ owner.**
- **Approvals recorded so far: none.** Nothing in `docs/MASTER_PRODUCT_DECISIONS.md`, the ledger, the PRs or this session's messages approves Z1–Z5. The 2026-11-28 "authorization and blocker closure" prompt asked for preparation and contained no approval.
- **This session prepared everything that needs no approval.** It applied, signed in to and wrote nothing.

| Z | Status | Exact scope | Environment | Files / objects | Depends on | Prepared without approval | To close it |
|---|---|---|---|---|---|---|---|
| **Z1** conversations and messages | **Awaiting owner approval** | R1-A participants immutable (trigger) · R1-B messages INSERT requires a participant (policy) · R1-C messages UPDATE: only `is_read` may change (trigger, strict until PD-B18) | local replay → QA (production is a separate decision) | `conversations`, `messages`; new migration ≥ 199; `supabase/expected_applied.json` | PD-B18 only to *relax* R1-C | drafts, static validation against every write path, rollback, pre-flight queries (`SECURITY_REMEDIATION_PLAN_2026-11-28.md` §2, §5); client write guard in #241 | apply in the authorized environment; probes show re-point, foreign post and foreign edit refused (42501); positive controls pass; live security suite |
| **Z2** set-log ownership | **Awaiting owner approval** | R1-D: a set log may be written only into the caller's own session (policy `WITH CHECK`) | local replay → QA | `workout_set_logs` policy; migration ≥ 199 | the pre-flight count (NULL or foreign-session rows) | draft, static validation, rollback, pre-flight query | cross-session insert/update refused; own sets save; history reads unchanged |
| **Z3** QA migration window | **Awaiting owner approval** (plus the QA database credential) | **Option S** 184 → 185, or **Option R** 182 → 183 → 184 → 185 → 186 (see the window brief); then R1-E (habit logs) | QA only | migrations 182–186 (authored, replay-verified, declared `excluded` with gates); `docs/QA_BATCH_182_184_185_RUNBOOK.md`; `docs/QA_184_185_WINDOW_DECISION_BRIEF.md` | the credential holder runs it (this session has no QA database credential); never `supabase db push` | complete runbook, brief and gates already exist; no change needed | apply in order; the gated live checks d08/d24/d25 turn strict and pass; move the frontier in `expected_applied.json` |
| **Z4** live-QA walkthrough | **Awaiting owner approval and access** | scenarios L1–L14 (`LIVE_QA_WALKTHROUGH_PLAN_2026-11-28.md`) on top of the 14-journey walkthrough | QA only; build `integration/p0-flutter-stack-rem1` @ `cfbac7c` | test accounts CoachA, CoachB, ClientC, ClientD, Admin, VendorE (owner-created; no credentials in any file) | L13 needs Z3; L14 needs Z1/Z2 applied | plan, evidence template, pass/fail rules | an evidence sheet per scenario; journeys count only under the walkthrough's PASS standard |
| **Z5** agent sign-in | **Awaiting owner action** | renew the Claude Code sign-in used by the background agents | this machine | `claude auth status`: logged in via claude.ai, **expires 2026-12-06 21:36 UTC** | — | status checked; the exact command is given | run `claude auth login` (or `claude setup-token`) yourself; then `claude auth status` shows a later `loginExpiresAt` |

## The one request
To approve, reply with any subset, using the exact wording or something just as specific:
1. **Z1:** "Approve R1-A [, R1-B] [, R1-C strict] as migration(s) ≥ 199: author, local replay, PR, then apply to **QA** after CI is green."
2. **Z2:** "Approve R1-D: same procedure, QA."
3. **Z3:**
   - "Approve a QA window for **Option S** (184 → 185)" or "**Option R** (182 → 186)", on [date].
   - Who runs it: you, or a named person with the QA database credential.
4. **Z4:**
   - "Approve live QA on **QA** in [window] for scenarios [L1–L12 | list] with accounts CoachA, CoachB, ClientC, ClientD, VendorE."
   - "Cleanup: yes / no."
   - "This session may / may not sign in and drive the web build."
5. **Z5:** renew the sign-in yourself before 2026-12-06 21:36 UTC.

Product decisions S1–S5 and wording U1–U13 are in `docs/proposals/OWNER_DECISION_BATCH_2026-11-28.md`. S4 (PD-B18) only affects relaxing R1-C, and S1 (PD8 server) is a separate migration.

**Production is not in scope** for any of these. It would need its own approval and its own procedure (RELEASE_GATES 9B.2).
