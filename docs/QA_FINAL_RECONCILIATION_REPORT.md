# 12CIRCLE FITNESS — QA FINAL RECONCILIATION REPORT

**Date:** 2026-09-27
**Branch:** `reconcile/12circle-integrated`
**HEAD:** `07f5bfb9115f74b3c3e262e1d0d3bc4607ffe99f` (unchanged by this mission)
**Scope:** 12 Circle Fitness only. Production ref `nxdbooufqzkpslkcogxc` never contacted.
**Status:** **QA NOT COMPLETE.** 3 findings opened, 1 opened-then-retracted, 2 prior
artefacts corrected. No remediation performed.

> **THIS IS NOT A HIPAA COMPLIANCE STATEMENT.** No compliance claim is made anywhere in
> this document.

---

## A · WHAT CHANGED IN THIS MISSION

Two blockers fell, both capability rather than analysis:

1. **Disk** — `~/.gradle/caches` (5.3 GB, disposable) cleared. Free space 633 MiB →
   **5,095 MiB**. Repository untouched. No APFS snapshot deleted (privileged boundary,
   documented and respected).
2. **Live database access** — `QA_DIRECT_DB_URL` was in `~/.zshrc` all along but invisible
   to `zsh -lc` (login ≠ interactive). `zsh -ic` exposes it.

Consequence: **every RLS claim in this programme's history had been inferred from migration
text; none had been read from a database.** They can now be read directly. The main value
delivered here is *verification of prior work* — including the discovery that one prior
conclusion was right for the wrong reason, and that one of my own new findings was not a
finding at all.

---

## B · METHOD, AND THE GUARDRAIL ON IT

All introspection ran with `default_transaction_read_only=on` set at session level and
verified in-band (`readonly=on`). The target was verified as QA (`eyqtldjqpgpljlqvpowh`)
with an explicit refusal branch on the production ref **before** connecting.

**The connection is `postgres`, which holds `rolbypassrls = t`. It was therefore used ONLY
to read the catalog** — `pg_policies`, `pg_proc`, `pg_class`, `information_schema`,
`storage.buckets`. **It was NOT used to perform any authorization test.** Reading a
policy's text is introspection; satisfying a policy as a superuser is defeating the test.
The governing instruction forbids the second and no probe here does it.

No write was attempted. No PHI value, credential, email or name is reproduced; identifiers
are truncated to 8 characters and data questions are answered with counts only.

---

## C · FINDINGS

### NEW-2 — self-assignment yields a READ of any coach's program · **HIGH** (IP, not PHI)

```
workout_program_assignments  "coaches manage assignments"
  cmd=ALL  USING (coach_id = auth.uid() OR client_id = auth.uid())  WITH CHECK = NULL
```

`WITH CHECK` is NULL, so Postgres reuses `USING` as the INSERT check, and
`client_id = auth.uid()` is satisfiable by anyone. Verified live that nothing obstructs it:

| Obstruction checked | Result |
|---|---|
| Triggers on the table | **0** — `coach_client_relationships` has `trg_relationship_integrity`; this table has nothing |
| Check constraints | **0** |
| `INSERT` granted to `authenticated` | **yes** |
| `program_id` / `client_id` / `coach_id` nullability | all nullable |
| `status` column exists | **yes — and the consumer ignores it** |

The consumer, `can_read_program(p_program)` (`STABLE SECURITY DEFINER`), returns true on
`EXISTS (… a.program_id = p_program AND (a.client_id = auth.uid() OR …))`, and it gates
SELECT on **`workout_programs`** and **`program_workouts`**.

**Composed:** any authenticated user inserts one row naming themselves `client_id` and any
`program_id`, and thereby reads that program and its full workout structure. No
relationship, no approval, no status check.

**What is and is not new.** The *policy* is already tracked — `F21_BLAST_RADIUS.md` §2a
lists it as "the proven one", and F-21b demonstrated the **write** direction (a client
created and cross-assigned a programme, all 201). **What is new is the read direction
against a program the attacker does not own**, via `can_read_program`. No existing document
joins self-assignment to a cross-coach read. This is the same *composition* class as the P0:
separately recorded facts that nobody had joined.

Coach-authored training content is **IP, not PHI** — this is not a HIPAA matter and not a P0.

**Evidence class: LIVE-CATALOG-CONFIRMED, NOT EXECUTED.** Demonstrating it needs an INSERT
into shared QA, declined earlier for F-03b; that decision is respected rather than routed
around.

### NEW-3 — `coach_reviews` has the cross-user-write shape and is untracked · **MEDIUM**

`coach_reviews "clients manage own reviews"` — `cmd=ALL`, `USING (client_id = auth.uid())`,
`WITH CHECK` NULL, **`coach_id` unpinned**. By `F21_BLAST_RADIUS.md`'s own taxonomy this is
class **2a** (cross-user write): the caller writes a row naming itself one party and **any
stranger** the other. A user may forge a review against any coach.

`recalc_coach_rating()` (SECURITY DEFINER, no status filter) then aggregates it into that
coach's `rating_avg` / `review_count` — both of which `public_profiles` publishes to every
authenticated account. Reputation and integrity, not confidentiality.

### NEW-4 — `workout_feedback`, same shape, untracked · **LOW**

`workout_feedback "users manage own feedback"` — `USING (user_id = auth.uid())`,
`WITH CHECK` NULL, **`coach_id` unpinned**. A user may attach feedback to an arbitrary
coach. **No read escalation**: selecting still requires `user_id = auth.uid()`, so the
attacker gains nothing readable. Data integrity only.

### NEW-6 — SEC-G1's population was never complete, because it filters on the policy NAME

This is the finding that produced NEW-3 and NEW-4, and it matters more than either.

The live catalog holds **37** policies with `cmd=ALL`, a `USING` clause and
`with_check IS NULL`. SEC-G1's baseline is **15**.

**This is NOT drift, and must not be raised as one.** The two measure different
populations: SEC-G1 additionally requires the policy *name* to contain
`coach|admin|head|team|vendor` and to carry no role helper. Most of the other 22 are
benign — a self-scoped `USING (user_id = auth.uid())` reusing itself as the INSERT check is
*correct*, since the caller can only name itself.

**But the name filter is load-bearing and wrong.** The dangerous shape is structural, not
lexical: *the `USING` clause pins one person-column while the row carries another that it
does not pin*. Computed live over all 37, the tables with an unpinned person-column are
`coach_team_members` (the P0), `action_items`, `coach_reviews`, `workout_feedback`, plus the
`OR`-shaped `workout_program_assignments`, `coaching_calls`, `client_habits`,
`client_nutrition_plans`.

**`coach_reviews` and `workout_feedback` appear in neither of `F21_BLAST_RADIUS.md`'s two
lists** — they escape solely because "clients manage own reviews" and "users manage own
feedback" sound self-scoped. A column-shape test catches them; a name test cannot.

So both SEC-G1's baseline of 15 and the blast-radius document's population **understate
the real one**, and the omissions are unguarded.

**The tracked count does not reconcile, so no new total is asserted here.**
`F21_BLAST_RADIUS.md` says "fifteen **tables**" (line 28) and "the fifteen **policies**"
(line 38), but its own enumeration is §2a (5 policies / 4 tables) + §2b (11 tables) =
**15 tables but 16 policies**. Live inspection compounds it: `coach_availability` carries
**two** matching policies ("Coaches manage own availability" and
"coach_manage_availability") where the document lists it once. Adding `coach_reviews` and
`workout_feedback` on top, the honest statement is that the population is understated by an
amount that should be **re-derived from the live catalog by column shape**, not incremented
by hand.

### NEW-1 — **RETRACTED IN FULL** (`public_profiles` RLS bypass)

I opened this as HIGH: `public_profiles` is `security_invoker=off`, owned by `postgres`
(`rolbypassrls = t`, `relforcerowsecurity = f`), has **no WHERE clause**, is granted to
`authenticated`, and projects 21 columns including `transformation_photo_urls` over all 15
profiles (8 of them non-coach). All of those facts are true. **The finding is still wrong,
on three independent grounds:**

1. **The design is deliberate and documented.** Migration 101 states it: *"The view
   deliberately runs with security_invoker = off, so it reads the base table as the view
   owner and is unaffected by the row restriction added in phase 3. Its safety comes from
   the column list."* The absent row predicate is the point — a member directory cannot
   work if every row is invisible. My "missing WHERE clause" framing was simply incorrect.
2. **A guard already covers it — SEC-G4** (`test/unit/rls_bypassing_view_guard_test.dart`).
   It names both bypassing views, explains the bypass mechanism, argues both are sound,
   identifies the real gap (*"their safety rests entirely on two comments… nothing enforces
   either"*), and pins the column list and the `shares_conversation_with` predicate. It even
   handles last-definition-wins across `CREATE OR REPLACE`. **My claim that the view layer
   "was never examined" was false**, and it was the premise of my severity rating.
3. **The one sensitive column is already an assigned owner decision — OD-58**
   (`SECURITY_LEDGER_PHI.md:126`), which records the public-bucket exposure *and* that the
   subjects are identifiable clients whose consent is the owner's question.

Additionally, the design's assumption holds on inspection: `transformation_photo_urls` is
written at exactly one site, `coach_business_screen.dart:137` (a coach-only self-write), so
the column comment *"public coach-marketplace fields (NULL for non-coaches)"* is accurate in
practice. Live: populated for **0 of 15**.

**What the live work did legitimately add here:** independent confirmation that SEC-G4's
model of the database is accurate — `security_invoker=off` on both views,
`security_barrier=true` on `conversation_participant_profiles`, `anon` denied,
`authenticated` granted, and **110's definition is the live one**, empirically confirming the
last-definition-wins hazard SEC-G4 was built around. That is verification of an existing
guard, not a new finding.

**Why this is recorded rather than deleted:** a retraction that leaves no trace teaches
nothing. The failure mode was mine and it is the one this programme keeps hitting — *I found
a real mechanism, did not check whether it was already known or intended, and rated severity
from my own ignorance of the ledger.* Checking the ledger and the write path before rating
severity is the discipline; it is the fifth retraction in this programme and the second
caused by not reading existing coverage first.

---

## D · A DEFECT IN THIS PROGRAMME'S OWN PROPOSED REMEDIATION

**`docs/proposed/SEC_PHI_1_roster_attendee_views.sql` is not merely "necessary but not
sufficient" — as written it is non-functional.**

The proposal creates two views `WITH (security_invoker = on)` **and** drops the
`is_team_lead_of` / `hosts_event_for` arms from the base `user_profiles` SELECT policy. Its
stated rationale: *"`security_invoker = on` so the view does NOT bypass RLS: the caller's own
permissions still apply."*

That is backwards for the purpose. With `security_invoker = on` the view applies **the
caller's** RLS on `user_profiles` — and after the arms are dropped, a team lead and an event
host are exactly the callers that policy now denies. **Both views return zero rows for
precisely the users they exist to serve**, as `200 []` — the silent "confident permanent
zero" this programme has documented repeatedly.

The house pattern, which SEC-G4 documents and the live catalog confirms, is the opposite:
`public_profiles` and `conversation_participant_profiles` both set `security_invoker=off`
deliberately, and the latter re-imposes a narrower gate *inside* the view
(`WHERE shares_conversation_with(id)`, plus `security_barrier=true`). SEC-PHI-1 cites that
view as its precedent while choosing the opposite setting.

**Correction required before the wave (not applied here):** `security_invoker = off`,
`security_barrier = true`, and carry the row predicate in the view's WHERE. The separately
recorded dependency on fixing `coach_team_members` first is unchanged and still governs.

**`SEC_PHI_9`'s open cast-hazard question is now answered:** `progress-photos` contains
**0 objects**, so its instruction to *"first confirm against live QA that every object has a
uuid first segment"* is only **vacuously** satisfied — a zero-row check licenses nothing
about future objects. Option **(b)** (a text-taking `is_active_coach_of(text)` overload that
returns false rather than raising) remains the recommendation and is now better supported.
Separately, 0 objects is consistent with the earlier throwaway-object probe's cleanup having
completed as recorded.

---

## E · THE 7 NOT-TESTABLE ITEMS — DISPOSITIONS

| # | Item | Previous state | New method | Result | Final disposition |
|---|---|---|---|---|---|
| 1 | F-03b live execution | source-inferred; write denied | live catalog read | `coach_team_members.with_check` **NULL**; `may_notify` body read — **no status filter on either anchor**; `notifications` INSERT = `may_notify(recipient_id)` | **NOT EXECUTED; upgraded to LIVE-CATALOG-CONFIRMED at all 3 links** |
| 2 | QAX-SEC-08 (P0) live execution | source-inferred; write denied | live catalog read | full chain confirmed: self-assertable insert → `is_team_lead_of` (**live body has no status/active check**) → `user_profiles` SELECT arm | **NOT EXECUTED; chain LIVE-CONFIRMED** |
| 3 | 22 PHI tables, no fixture rows | PARTIAL | universal catalog query | **0** public tables with RLS disabled; **0** anon grants on any public table | **COVERAGE CONVERTED** (universal, not sampled). Per-table boundary *correctness* still undemonstrated |
| 4 | active-coach / team-lead / event-host arms | "needs `QA_SERVICE`" | live rows + columns | **active-coach: UNBLOCKED** (an `active` relationship exists, `f626acd9`→`5470a95f`). **team-lead: still 0 rows.** **event-host: PROVABLY UNREACHABLE** — `events.vendor_id` is **NULL** on both events, so `hosts_event_for()` can never be true | **1 unblocked, 1 needs a fixture, 1 reclassified** |
| 5 | Cloud replay harness | BLOCKED (no Postgres server) | — | still none; Docker down | **STILL BLOCKED**, largely *moot*: its schema-verification purpose is better served by direct introspection; unique remaining value is fix-**simulation** |
| 6 | All app runtime | BLOCKED (disk 313–635 MiB) | disk reclaimed | `flutter test` → **1,675 pass / 9 skipped**, 1:13. Disk 5094 → 5089 MiB | **CONVERTED** |
| 7 | private-vs-absent bucket distinction | unresolvable by HTTP probe | `storage.buckets` read | `avatars`/`coach-media`/`exercise-media` **public**; `chat-media`/`progress-photos` **private** | **CONVERTED** — settled from the catalog |

**Item 4 is the cautionary one.** `event_registrations` went 0 → 2 rows, which looked like
an unblock. It is not: `vendor_id` is NULL, so the arm stays unreachable. **A row count is
not a capability.** Recording it as newly-testable would have manufactured a conversion.

**Item 3, honestly stated:** "0 tables with RLS disabled" is a *stronger class* of evidence
than the per-table probing originally planned (universal, not sampled), but it answers a
different question. It proves RLS is *enabled* everywhere; it does not prove each policy
expresses the right boundary. NEW-2/3/4 are policies that are enabled and wrong.

---

## F · CORRECTIONS AND CONFIRMATIONS

**Corrections to my own prior work:**

1. **NEW-1 retracted in full** — see §C. Premise false (SEC-G4 exists), design deliberate
   (101), sensitive column already an owner decision (OD-58).
2. **`may_notify` "mentions status" was my detector matching a comment.** An automated check
   reported `mentions_status = true`; the live body shows *status* appears only in prose, in
   a comment explaining a **deliberate** non-filtering of `class_bookings`. Neither the
   `coach_client_relationships` arm nor the `coach_team_members` arm filters status (the
   latter has no status column at all). **F-03b is unchanged and confirmed.** This is the
   sixth time in this programme a detector has read its own prose as evidence.
3. **The prior report's denominator does not reconcile with its own arithmetic.**
   `QA_COMPLETION_REPORT_2026-09-27.md` §13 divides by **19** while enumerating
   13 COMPLETE + 4 PARTIAL + 2 NOT-EVIDENCED + 2 BLOCKED = **21**. Its 78.9% and 84%
   inherit that error. Recomputed in §G.
4. **SEC-G1's baseline of 15 and `F21_BLAST_RADIUS.md`'s population understate the real one
   by two** (NEW-6). Not drift — incompleteness by construction.

**Prior conclusions now verified against the live database:**

| Prior claim | Live result |
|---|---|
| SEC-DRIFT-1 **retraction** was correct (074's `format('%I')` loop does create RLS) | **CONFIRMED** — all 5 AI tables `relrowsecurity = t`, 1 policy each |
| `is_team_lead_of` has no status/active condition | **CONFIRMED** verbatim from `pg_get_functiondef` |
| Exactly 5 policies join `coach_client_relationships` without the helper; 3 check status, 2 do not | **CONFIRMED** — `score_events` and `storage.objects` omit it; `coach_exercise_media`, `custom_exercises`, `user_profiles`(UPDATE) all require `status='active'` |
| `coach_team_members` "Head coach manages team" is `FOR ALL` with no `WITH CHECK` | **CONFIRMED** — `with_check` is NULL |
| SEC-PHI-10 (`score_events`) is INCONCLUSIVE, not reproduced | **CONFIRMED, with a sharper reason** — 8 events exist but all belong to `5470a95f`, whose relationship is **active** (where coach access is *correct*); the `cancelled` client `1c89c873` has **0** events. Fixture misalignment, not absence of the defect |
| No SECURITY DEFINER function has a mutable `search_path` | **CONFIRMED** — 0 found |
| `anon` has no grants on public tables | **CONFIRMED** — 0 found |
| SEC-G4's model of the two bypassing views | **CONFIRMED** — including that `110`'s definition is the live one |

---

## G · RECALCULATED COMPLETION

Denominator corrected to the **21 domains the prior report actually enumerated** (it divided
by 19). No domain is added: the view layer, which I briefly believed was unexamined, is
already covered by SEC-G4.

| Domain | Prior | Now | Basis |
|---|---|---|---|
| 13 already COMPLETE | 13.0 | 13.0 | unchanged |
| PHI table access | 0.5 | **0.75** | universal live RLS coverage + all policy text read live; per-table boundary correctness still undemonstrated |
| AI / processors | 0.5 | 0.5 | unchanged — disclosure is owner-side |
| Privacy alignment | 0.5 | 0.5 | unchanged |
| Test completeness | 0.5 | 0.5 | full suite now runs (1,675 pass), **offset** by NEW-6 (SEC-G1 understates by 2) and CHAIN-G1's known `notifications` gap |
| Supply chain | 0 | **0.5** | `npm audit` run — 17 advisories (7 high, 9 moderate, 1 low); **no SBOM** — `cyclonedx-npm`, `syft`, `trivy`, `cdxgen` all absent |
| CI/CD | 0 | **1.0** | 7 jobs enumerated; run `36093979157` inspected; `static-guards` FAILURE root-caused to QAT-1; `main` has **no branch protection** |
| App runtime | 0 (blocked) | **1.0** | suite executed after disk recovery |
| Replay harness | 0 (blocked) | **0.5** | still blocked for fix-simulation; schema purpose superseded |

**18.25 / 21 = 86.9%**

Read this carefully: **the percentage rose while the open-defect count rose.** The increase
is almost entirely CI/CD and runtime becoming *evidenced*. A higher number means more of the
surface has been looked at — **not** that the system is safer. Three new findings and a
retraction say otherwise.

**The remaining 13.1% is named, not unexamined:** SBOM tooling absent; replay
fix-simulation blocked (Docker); `coach_team_members` and `events.vendor_id` fixtures
absent; `score_events` rows for the cancelled-relationship client absent; per-table PHI
boundary demonstrations requiring writes that were declined.

---

## H · GOVERNANCE — WHAT WAS NOT DONE, AND WHY

| Boundary | Action |
|---|---|
| Production ref `nxdbooufqzkpslkcogxc` | **never contacted.** Explicit refusal branch ran before connecting |
| Privileged credentials to satisfy a policy | **refused.** `postgres` / `QA_SERVICE` used for catalog reads only; no authorization test performed with them |
| Writes to shared QA (F-03b, QAX-SEC-08, NEW-2 proof) | **not attempted.** Previously declined; not routed around |
| APFS snapshots (3, incl. a staged macOS update) | **not deleted.** Privileged boundary, documented |
| Remediation / application code changes | **none** |
| Commits, pushes, branches, history rewrite | **none** |

**Git stop conditions verified:** HEAD `07f5bfb9115f74b3c3e262e1d0d3bc4607ffe99f`, branch
`reconcile/12circle-integrated`, **0 tracked modifications**. Untracked: this report, two
pre-existing untracked docs, and `d09-assessment-access.mjs` (another workstream's, backed
up externally with SHA-256 recorded).

---

## I · RECOMMENDED NEXT ACTIONS

1. **`coach_team_members` `WITH CHECK`** — still first. One change closes the P0
   (QAX-SEC-08) **and** F-03b. Needs OD-14 + OD-QAX-9 and a wave number.
2. **Correct `SEC_PHI_1` before scheduling it** (§D) — as written it breaks both screens it
   exists to preserve.
3. **NEW-2** — add `WITH CHECK` to `workout_program_assignments` and a status predicate to
   `can_read_program`'s assignment arm.
4. **`SEC_PHI_9` / `SEC_PHI_10`** status predicates, using option (b).
5. **Convert SEC-G1 from a name test to a column-shape test** (NEW-6) — it would then catch
   `coach_reviews` and `workout_feedback`. **Re-derive the population from the live catalog
   rather than incrementing the baseline**: the current 15 conflates tables with policies and
   misses a duplicate on `coach_availability`. Reconcile `F21_BLAST_RADIUS.md`'s §2a/§2b
   against that. Widen CHAIN-G1 to `notifications`.
6. **QAT-1** — repoint `apps/mobile/tool/anon_least_privilege.py` so `static-guards` passes;
   the gate's own rule forbids silencing it with an allowlist entry. Then consider branch
   protection on `main`, which currently has none.
7. SBOM tooling; `npm audit` remediation for the 7 high advisories.
8. **Fixtures that would convert what remains:** a `coach_team_members` row, an
   `events.vendor_id`, and `score_events` rows for the `cancelled`-relationship client.

---

*No finding here is a compliance conclusion. Three findings are newly opened and
unremediated; one was opened and retracted in full; two prior artefacts are corrected.
QA remains incomplete.*
