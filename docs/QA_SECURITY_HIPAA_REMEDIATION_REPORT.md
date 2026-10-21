# 12Circle Fitness — Security / HIPAA Remediation Report

**Phase:** TRIAGE → AUTHORIZE → REMEDIATE → MUTATE → VERIFY
**Branch** `chore/qa-environments-secure-ai-backend` · **entry HEAD** `9fb7260`
**Live evidence:** QA project `eyqtldjqpgpljlqvpowh`, read-only. Production
`nxdbooufqzkpslkcogxc` **never contacted.**

> **This is a technical control assessment, not a legal HIPAA compliance
> certification.** Controls requiring legal review are marked OWNER_DECISION.

---

## Headline

**Two of the four findings the previous phase called "new" do not survive
re-verification.** Re-verifying before remediating was the right instruction and
it changed the outcome: the most severe finding in the prior report — **SEC-DRIFT-1**
— is a **FALSE_POSITIVE**, and no migration was written for a problem that does
not exist.

Two real defects were fixed, mutation-tested, and one of them contained a trap
that would have reintroduced a previously-closed bug.

---

## A. Exact baseline

| | Entry | Exit |
|---|---|---|
| HEAD | `9fb7260` | `a857993` |
| Tests | 1,612 pass / 9 skipped | **1,622 pass / 9 skipped** |
| Analyzer errors | 0 | **0** |
| Guard tests (`test/unit/*guard*`) | 33 | **35** |
| Migrations applied by me | — | **none** |
| Production code files changed | — | 3 |

---

## B. Concurrency state

- Working tree clean except `supabase/tests/security/d09-assessment-access.mjs`
  (untracked, another workstream's) — **not touched**.
- Second worktree `/private/tmp/12circle-wrk02-negative-control` @ `70a647b`
  (detached, prunable) — **not touched**.
- Only commit since the exhaustion report was my own. No concurrent agent
  activity observed.
- Files read as evidence and **not modified**: `N07_IMPLEMENTATION_STATUS.md`,
  `proposed/N07_assessment_access.sql`, `FINAL_NEW_SCREEN_DESIGN_COMMISSION.md`,
  `MASTER_REMEDIATION_*`.

---

## C. Finding register

| ID | Class | Status |
|---|---|---|
| **SEC-DRIFT-1** | **F** | **FALSE_POSITIVE — retracted, see §S** |
| **SEC-PHI-5** (RLS half) | **F** | **FALSE_POSITIVE — claim substantiated** |
| **SEC-VOICE-2** | **A** | **FIXED** (`a2bfada`… `a2bfada`) |
| **OD-60** (error contract half) | **A** | **FIXED** (`a857993`) |
| **OD-60** (discoverability half) | C | OWNER_DECISION |
| SEC-AI-1 | C | OWNER_DECISION — re-verified, stands |
| SEC-PHI-1 | B | **PROPOSED** — `docs/proposed/SEC_PHI_1_roster_attendee_views.sql` |
| SEC-VOICE-1 (bucket) | B | FIXED_PENDING_MIGRATION — blast radius now reduced |
| SEC-PHI-3 / N-07 | B | BLOCKED (migration not applied) |
| SEC-PHI-AUDIT | B | BLOCKED |
| SEC-PHI-4 | C | OWNER_DECISION |
| SEC-MEDIA-1 (avatars) | B | PROPOSED-ADJACENT — see §Q |
| OD-57 / OD-58 / OD-59 / OD-61 | C | OWNER_DECISION |
| 22 undemonstrated tables | D | NOT_DEMONSTRATED — needs `QA_SERVICE` |

---

## D. HIPAA / security control matrix

| # | Control | Status |
|---|---|---|
| 1 | Authentication | VERIFIED (live, 5 identities) |
| 2 | Authorization | VERIFIED for tested arms; NOT_DEMONSTRATED for 3 |
| 3 | Least privilege (anon) | VERIFIED — `42501` on every PHI table |
| 4 | Client↔client isolation | VERIFIED (live, negative) |
| 5 | Coach↔client isolation | PARTIALLY VERIFIED — active-coach arm untestable |
| 6 | Relationship revocation | **VERIFIED** — former coach denied everything |
| 7 | PHI table access | PARTIALLY VERIFIED |
| 8 | PHI column exposure | **FAILED** — SEC-PHI-1 (full row to vendors/team leads) |
| 9 | RLS coverage | **VERIFIED** — all 92 created tables carry an RLS statement |
| 10 | SECURITY DEFINER review | VERIFIED — 97 functions, none granted to anon |
| 11 | RPC EXECUTE | VERIFIED — every UUID-accepting fn refuses non-admins |
| 12 | Storage bucket privacy | **FAILED** — `coach-media` public |
| 13 | Signed URLs | VERIFIED (locally) — voice, video, chat, progress |
| 14 | Public URLs | PARTIALLY VERIFIED — 3 remain, each assessed (§Q) |
| 15 | Voice recordings | **FIXED** — SEC-VOICE-2 |
| 16 | Video responses | FIXED previously; OD-57 open |
| 17 | AI-provider transmission | **FAILED (disclosure)** — SEC-AI-1 |
| 18 | AI memory storage | VERIFIED — RLS `FOR ALL USING (user_id = auth.uid())` |
| 19 | AI memory deletion | **FIXED** — error contract; OD-60 design open |
| 20 | Audit logging | **FAILED** — no audit table exists |
| 21 | Access logging | **FAILED** — same |
| 22 | Account deletion | FAILED (no in-app path) — OWNER_DECISION |
| 23 | Data export | FAILED (none anywhere) — OWNER_DECISION |
| 24 | Data retention | OWNER_DECISION — policy describes an email-only path |
| 25 | Error-message leakage | VERIFIED — ERR-G2, 38 sites closed, green |
| 26 | Local storage | VERIFIED — 0 PHI persisted locally |
| 27 | Notifications | VERIFIED — 0 PHI in any notification body |
| 28 | Analytics / telemetry | VERIFIED — release build emits nothing |
| 29 | Secrets / service-role | VERIFIED — no service key in the app or env |
| 30 | `search_path` pinning | VERIFIED — migration 118 catch-all loop |
| 31 | Migration reproducibility | **VERIFIED** — see §S |
| 32 | QA/live schema drift | **NONE FOUND** — §S |

---

## E. Findings re-verified (and two retracted)

### SEC-DRIFT-1 → **FALSE_POSITIVE**

The previous report claimed `ai_memories`/`ai_profiles` isolate per user on live
QA while **no migration creates that protection**, and escalated it: an
environment built from migrations alone would expose auto-captured injury
records, and `deleteMemory`'s `delete().eq('id', id)` would become a cross-user
delete.

**It is created by a migration.** `074_ai_coaching_layer.sql:73–81`:

```sql
foreach t in array array['ai_profiles','ai_memories','ai_insights',
                         'ai_reviews','ai_goal_predictions'] loop
  execute format('alter table %I enable row level security', t);
  execute format($f$create policy "own ai data" on %I for all to authenticated
                    using (user_id = auth.uid())
                    with check (user_id = auth.uid())$f$, t);
end loop;
```

**Why it was missed:** the detection grep required the table name and the RLS
keyword on the *same line*. Here the table names live in a `text[]` and the
statement is built by `format()` with `%I`, so no line contains both. The same
pattern covers nine `exercise_*` tables.

Answering Phase 3's questions directly:

1. What creates the live protection? — migration 074.
2. Undocumented manual change? — **No.**
3. Supabase config outside migrations? — **No.**
4. Inherited from another migration? — **Yes, 074.**
5. Can a clean rebuild reproduce it? — **Yes.**
6. Is `deleteMemory` safe on a clean rebuild? — **Yes.** The policy is `FOR ALL`,
   so it constrains DELETE, not just SELECT.

**No migration was authored for this.** Re-verification is what prevented it.

### SEC-PHI-5 (RLS half) → **FALSE_POSITIVE**

With DO-block loops counted, **all 92 created tables** have an RLS statement.
The Privacy Policy's §7 *"row-level security policies on all database tables"*
is substantiated. Its TLS-1.3/AES-256 claims remain **NOT_DEMONSTRATED**
(platform properties, not verifiable from this repository).

### Findings that survived re-verification

| Finding | Re-verification |
|---|---|
| SEC-AI-1 | **STANDS.** Zero mentions of Anthropic or any model provider in the legal screens. §2 discloses AI *use*; §6 implies *"aggregate, anonymised"* data trains *"our AI models"*. §3's processor list names Supabase, Expo, analytics. |
| SEC-VOICE-2 | **STANDS** — confirmed by direct source read, then fixed. |
| SEC-PHI-1 | **STANDS and sharpened** — both rosters consume 4 columns; the policy grants the whole row. |
| SEC-PHI-4 | **STANDS** — Account section still holds exactly 3 rows. |
| SEC-PHI-AUDIT | **STANDS** — no audit table, live. |

---

## F. Findings fixed

### SEC-VOICE-2 — `a2bfada` — **FIXED / LOCALLY_VERIFIED**

`uploadCoachVoice` returned `getPublicUrl(path)` and `setCoachVoice` persisted it
into `coach_exercise_media.voice_url`. Every row held a permanent
unauthenticated link to a recording of a coach's voice, on a bucket confirmed
public. The previous wave recorded SEC-VOICE-1's "Dart prerequisite" DONE having
done only the *display* half — **signing a value at render time does nothing
about the value already in the database.**

It now stores the object path. No migration required: both readers normalise
either form, so legacy rows keep working.

**The trap.** Changing the upload alone silently breaks deletion.
`clearCoachVoice` resolved its delete target with `coachVoiceObjectPath`, which
parses the public-URL form **only**. Given a bare path it returns `null`,
`remove()` is skipped, the row is nulled, and the method still returns `true` —
the app claiming a deletion it did not perform and leaving audio in a public
bucket. That is exactly the defect `coach_voice_deletion_guard_test` exists to
close, reintroduced by a one-line fix elsewhere. The delete path now uses the
both-forms normaliser.

The existing deletion guard **caught this**, and was strengthened rather than
relaxed: it now requires the both-forms normaliser and forbids the URL-only
parser. Its fixed 1,400-character window was replaced with real method-body
extraction — a comment had pushed `.remove([path])` outside it, and a guard a
comment can break is a guard that gets edited to pass.

### OD-60 (error contract) — `a857993` — **FIXED / LOCALLY_VERIFIED**

`deleteMemory` returned `void` and ended in `catch (_) {}`. These rows are health
facts — `kind` includes `injury`, captured **automatically** by the `ai-coach`
edge function — and the long-press is the member's only control over them. A
failed delete was indistinguishable from a success: the chip reappeared after
the refresh with no explanation. It now returns `bool` (matching `addMemory`
beside it) and the screen reports failure.

---

## G. Findings not fixed, with reasons

| Finding | Why not |
|---|---|
| SEC-PHI-1 | Schema change; `132+` is assigned at wave entry. **Proposal authored** (§I). |
| SEC-VOICE-1 (bucket) | Migration. Proposal already exists. |
| SEC-PHI-3 / N-07 / SEC-PHI-AUDIT | Migration not applied; the RPC does not exist live. |
| SEC-AI-1 | Disclosure + processor agreement — legal, not code. **I did not touch legal copy.** |
| SEC-PHI-4 | Building controls or editing legal copy — both owner decisions. |
| OD-60 (discoverability) | A long-press with no affordance is a design decision. |
| OD-57/58/59/61 | Product decisions. |
| SEC-MEDIA-1 | Bucket privacy = migration. |

---

## H. Owner decisions

1. **SEC-AI-1** — name Anthropic (and Resend, Google) as processors; confirm an
   agreement covering health data. *Technical fact: identifiable injuries, pain,
   allergies, `cycle_logs`, weight and nutrition are transmitted. Legal
   conclusion: not mine to draw.*
2. **SEC-PHI-4** — reconcile Terms §9 and Privacy §5 Access with reality.
3. **SEC-PHI-1 residual** — should an event vendor receive an attendee's
   **email**? The proposal preserves current behaviour and flags it.
4. **OD-60** — is a hidden long-press an adequate control over health data?
5. **OD-57 / OD-59** — build the video player and coach feedback view, or remove.
6. **OD-58** — may `transformation_photo_urls` stay public?
7. **OD-61** — `marketplace_coaches` exposes each coach's `plan_tier`/`rank_score`.

---

## I. Migration proposals

| File | Status |
|---|---|
| `docs/proposed/SEC_PHI_1_roster_attendee_views.sql` | **NEW — AUTHORED, UNNUMBERED, NOT APPLIED** |
| `docs/proposed/SEC_VOICE_1_coach_media_private.sql` | pre-existing, unnumbered |
| `docs/proposed/N07_assessment_access.sql` | another workstream's |

The SEC-PHI-1 proposal creates `team_member_profiles` and
`event_attendee_profiles` (`security_invoker = on`, four columns each) and drops
the two wide arms, keeping `id = auth.uid()` and `is_active_coach_of(id)`.

It carries an explicit **integration warning**: both call sites reach
`user_profiles` through a PostgREST *embedded resource*, which resolves against
the base table. A view has no foreign key for PostgREST to traverse, so those
two reads will likely need to become two-step queries. That must be prototyped
before the migration is scheduled — the SEC-VOICE-2 lesson, where the one-line
change was safe and the resolver on the other side of it was not.

---

## J. Live QA evidence (carried forward, re-used not re-run)

anon `42501` on every PHI table · former coach denied everything ·
`invite_token` withheld from all five identities · every UUID-accepting RPC
refuses non-admins · `coach-media` public · N-07 RPC absent (`PGRST202`) ·
no audit table (`PGRST205` × 7).

---

## K. Runtime evidence

**NONE. BLOCKED — and the blocker has worsened.**

| | At audit | Now |
|---|---|---|
| Free disk | 1.3 GiB (93 %) | **767 MiB (96 %)** |
| Docker | unavailable | **unavailable** |
| Booted simulators | 0 | **0** |

A build needs ~2.67 GiB and an emulator ~7.4 GiB. No build was attempted; doing
so would likely exhaust the volume. The project's own caches are **not** the
cause (`.dart_tool` 267 MB, `build` 95 MB) — the pressure is system-wide.

**Nothing in this report is marked RUNTIME_VERIFIED.** The two fixes are
**LOCALLY_VERIFIED**: suite, analyzer and mutation testing, not a running app.

---

## L. Mutation-test results

| Suite | Mutation | Result |
|---|---|---|
| VOICE-G2 | restore `getPublicUrl` in the upload | KILLED |
| VOICE-G2 | **regress the delete resolver to the URL-only parser** | **KILLED** |
| VOICE-G2 | make the resolver accept any value | KILLED |
| VOICE-G2 | drop coach/exercise scoping from the path | KILLED |
| AIMEM-G1 | restore the silent catch | KILLED |
| AIMEM-G1 | screen discards the result | KILLED |
| AIMEM-G1 | open the READ/DELETE clause to `using (true)` | **SURVIVED → fixed → KILLED** |
| AIMEM-G1 | open the WRITE clause | KILLED |
| AIMEM-G1 | narrow the policy off DELETE | KILLED |
| AIMEM-G1 | drop `ai_memories` from the RLS loop | KILLED |

**10 mutations, 10 killed after one repair.** The AIMEM survivor is worth
recording: asserting the bare predicate `user_id = auth.uid()` passed while the
read clause was opened to `using (true)`, because the same predicate also appears
in `with check` and a substring match still matched. Each clause is now asserted
as a unit.

---

## M. Remaining blockers

| Blocker | Blocks | Lifts when |
|---|---|---|
| Migration numbering `132+` | SEC-PHI-1, SEC-VOICE-1(b), N-07, SEC-PHI-AUDIT, SEC-MEDIA-1 | wave entry |
| `QA_SERVICE` absent | 22 undemonstrated tables; active-coach/team-lead/event-host arms | key provided |
| Docker unavailable | schema read, local stack | Docker runs |
| Disk 767 MiB | all runtime verification | ≥ 10 GiB free |
| Production forbidden | any prod claim | explicit owner authorization |

---

## N. Remaining risks

1. **PHI column over-exposure** (SEC-PHI-1) — highest unmitigated technical risk:
   an event vendor can read an attendee's PAR-Q, with no time bound and no
   revocation path.
2. **No auditability** — a PAR-Q read leaves no record at all.
3. **`coach-media` public** — SEC-VOICE-2 stops *new* rows carrying public URLs,
   but **rows written before it still hold live unauthenticated links**, and the
   objects remain publicly fetchable until the bucket is privatised.
4. **Undisclosed processor** (SEC-AI-1).
5. **Three arms and 22 tables never demonstrated** — absence of evidence.

---

## O. N-07 status — **BLOCKED**

`get_client_assessment` does not exist live (`PGRST202`); `assessment_access_log`
does not exist (`PGRST205`). The base-table policy remains the only path.
Former-coach denial is **VERIFIED**; unassigned-coach, team-lead and event-host
denial are **NOT_DEMONSTRATED**. Not implemented, not claimed verified.

---

## P. AI-provider PHI findings — **OWNER_DECISION**

| Field | Provider | Endpoint | Trigger |
|---|---|---|---|
| injuries, pain, soreness, allergies | Anthropic | `/v1/messages` | **automatic** — `ai-coach` scans every message |
| `cycle_logs` (menstrual) | Anthropic | `/v1/messages` | automatic — context assembly |
| weight, nutrition, habits, goals, scores | Anthropic | `/v1/messages` | automatic |
| email + notification bodies | Resend | `/emails` | server-triggered |
| exercise search terms | Google | YouTube API | enrichment |

Stored in `ai_memories`, identity-bound, RLS-protected (074), user-visible,
user-deletable (now with a truthful failure path). **Not disclosed** in the
Privacy Policy's processor list. Data minimisation is possible in principle but
would change what the coach can reason about — a product decision, recorded, not
taken.

---

## Q. Storage / media findings

| Path | Status |
|---|---|
| coach voice | **FIXED** — stores object path, signs at render |
| coach video | FIXED previously |
| `coach-media` bucket | **FAILED** — public; migration-blocked |
| `avatars` | `"$uid/avatar.$ext"` on a public bucket — **anyone holding a UUID can fetch the photo unauthenticated.** SEC-MEDIA-1, migration-blocked |
| `exercise-media` | public; global library — appropriate |
| `transformation_photo_urls` | OD-58 |
| `progress-photos`, `chat-media` | signed URLs, not publicly served |

**Blast radius of privatising `coach-media` is now:** voice signs ✓, video has no
reader ✓, only OD-58's marketing photos remain in question.

---

## R. Data-subject-control findings

| Claim | Actual capability | Impact | Decision required |
|---|---|---|---|
| Terms §9 — delete from *Profile → Settings → Account* | **No such control** | Members cannot exercise deletion where told | Build it, or correct the Terms |
| Privacy §5 Access — export from *Profile → Settings → Account* | **No export control anywhere** | Portability unavailable at the stated path | Build it, or correct the copy |
| Privacy §5 Deletion — email `privacy@12circle.app` | **ACCURATE** | — | none |
| Privacy §6 — purge within 30 days of deletion | Reachable only by email | Commitment attaches to a manual path | Confirm the operational process |
| Privacy §7 — RLS on all tables | **SUBSTANTIATED** | — | none |

No backend deletion or export path exists in `supabase/functions/` or
`apps/api/`. **No UI was invented and no legal language was altered.**

---

## S. QA / live-schema drift — **NONE FOUND**

The previous phase's drift finding is **retracted** (§E). Every table's RLS is
created by a migration, including the 14 covered by DO-block loops. **Migration
reproducibility: VERIFIED.** A database rebuilt from this repository reproduces
the protections observed live.

The genuine lesson is about detection, not drift: a grep requiring a table name
and an RLS keyword on one line cannot see `format('alter table %I …', t)` driven
by an array.

---

## T. Next-phase recommendations

1. **Assign a wave number** and land, in this order: SEC-VOICE-1(b) bucket
   privatisation (blast radius is now minimal), then SEC-PHI-1's views **with the
   PostgREST embedding prototype done first**, then N-07 + `assessment_access_log`.
2. **Provide `QA_SERVICE` and seed fixtures** — one active coach↔client pair, one
   `coach_team_members` row, one `event_registrations` row. That single step
   converts three untested authorization arms and 22 tables from
   NOT_DEMONSTRATED to testable. *Without it no future wave can do better than
   this one.*
3. **Reclaim disk** — runtime verification has now been blocked across three
   consecutive phases and the margin is shrinking.
4. **Owner decisions** in §H, SEC-AI-1 first.
5. **Backfill** `coach_exercise_media.voice_url` — pre-SEC-VOICE-2 rows still hold
   public URLs. The readers tolerate them, so this is cleanup, not a blocker, but
   those links stay live until the bucket is private.

---

## Final status

Two defects fixed and mutation-tested. Two prior findings retracted on
re-verification, one of which would have produced an unnecessary migration
against a non-existent problem. Everything remaining is a migration-number
assignment, an owner decision, a credential, or an environmental capability —
each named with the condition that lifts it.

**SECURITY QA EXHAUSTED — OPEN FINDINGS REMAIN.**

This is **not** "all findings fixed", and it is **not** a claim of HIPAA
compliance. The controls in §D marked FAILED are unmitigated today.
