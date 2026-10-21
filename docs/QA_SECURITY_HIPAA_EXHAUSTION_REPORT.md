# 12Circle Fitness — Security / HIPAA Exhaustion Audit

**Phase:** DISCOVER → VERIFY → DOCUMENT. **No remediation performed.**
**Branch** `chore/qa-environments-secure-ai-backend` · **HEAD** `0088089`
**Live environment probed:** QA project `eyqtldjqpgpljlqvpowh` — **read-only, GET/STABLE only**
**Production ref `nxdbooufqzkpslkcogxc` was never contacted.**

> **This report does not claim HIPAA compliance and is not a compliance certification.**
> It records technical facts, the evidence for each, and what could not be established.

---

> ## ⚠ CORRECTION — 2026-09-24, issued by the remediation phase
>
> **Two findings below are WRONG and are retracted.** Corrected in
> `QA_SECURITY_HIPAA_REMEDIATION_REPORT.md` §E. The text is left in place
> unedited so the error is legible rather than erased.
>
> **1. `SEC-DRIFT-1` is a FALSE POSITIVE.** §1 and §15 claim `ai_memories` /
> `ai_profiles` isolate per user on live QA while *"no migration in the
> repository enables RLS or creates a policy on them"*. **A migration does.**
> `074_ai_coaching_layer.sql:73–81` runs a `DO` block that enables RLS and
> creates `"own ai data" … FOR ALL … USING (user_id = auth.uid())` across all
> five AI tables. The detection grep required the table name and the RLS keyword
> on the **same line**; here the names live in a `text[]` and the statement is
> built by `format()` with `%I`, so no single line contains both.
>
> Everything that followed from it is therefore also wrong: a clean database
> rebuilt from these migrations **does** reproduce the protection, and
> `deleteMemory`'s `delete().eq('id', id)` **is** constrained — the policy is
> `FOR ALL`, so it covers DELETE.
>
> **2. `SEC-PHI-5`'s RLS half is a FALSE POSITIVE.** Counting DO-block loops,
> **all 92 created tables** carry an RLS statement, so Privacy §7's *"row-level
> security policies on all database tables"* is substantiated. Its TLS-1.3 /
> AES-256 claims remain NOT_DEMONSTRATED.
>
> §14 of this report argues that an instrument must be shown capable of
> producing a non-empty result before an empty one is believed. **That standard
> was not applied to the RLS scan itself**, and the live probe that contradicted
> it was read as evidence of drift rather than as evidence the scan was broken.
>
> The findings that **do** survive re-verification: `SEC-AI-1`, `SEC-VOICE-2`,
> `SEC-PHI-1`, `SEC-PHI-4`, `SEC-PHI-AUDIT`, `SEC-MEDIA-1`, `OD-60`.

---

## 1 · Executive summary

Five identities were authenticated against the live QA database and used to test real
role boundaries — the first wave in this programme able to do so. That produced strong
positive results **and** four new findings, two of which correct conclusions recorded as
closed.

**The three findings that matter most:**

1. **SEC-AI-1 — an undisclosed sub-processor receiving health data.** The Privacy Policy's
   processor list is Supabase, Expo and "selected analytics providers". Identifiable
   injuries, pain, allergies, menstrual cycle logs, weight and nutrition are transmitted
   to **`api.anthropic.com`**, which appears nowhere in the policy. Resend and Google/
   YouTube are also undisclosed.
2. **SEC-DRIFT-1 — protection that exists in QA but in no migration.** `ai_memories` and
   `ai_profiles` demonstrably isolate per user on live QA, yet **no migration in the
   repository enables RLS or creates a policy on them.** An environment built from
   migrations alone would not have that isolation — and `ai_memories` holds
   auto-captured **injury** records.
3. **SEC-VOICE-2 — a "DONE" item that was half done.** `uploadCoachVoice` still stores
   `getPublicUrl(...)`. Last wave added render-time signing and recorded the Dart
   prerequisite complete; the *stored value* was never changed. Its sibling video path
   now stores an object path, so the two are inconsistent, and `coach-media` is
   **confirmed public today**.

**Strong positives, live-verified:** anonymous callers are denied at GRANT level on every
PHI table; a **former coach** is denied everything; `invite_token` is withheld from every
identity including admin; every UUID-accepting RPC refuses non-admins.

**Status: SECURITY QA EXHAUSTED — OPEN FINDINGS REMAIN.**

---

## 2 · Baseline (re-measured, not inherited)

| | |
|---|---|
| Branch / HEAD | `chore/qa-environments-secure-ai-backend` / `0088089` |
| Working tree | clean except `supabase/tests/security/d09-assessment-access.mjs` (untracked, another workstream's) |
| Worktrees | this one, plus `/private/tmp/12circle-wrk02-negative-control` (**another agent's — not touched**) |
| Tests | **1,612 pass / 9 skipped** |
| Analyzer | **0 errors** (312 infos, pre-existing) |
| Guard tests | 33 |
| Migrations | 132 files; `132+` reserved for wave entry |
| Disk | **1.3 GiB free, 93 % used** |
| Docker | **NOT AVAILABLE** |
| Devices/simulators | **none booted** |
| `QA_SERVICE` key | **absent** from every env file |

---

## 3 · Scope

Covered: PHI inventory, RLS under five real identities, SECURITY DEFINER/RPC surface,
storage buckets, N-07, data-subject controls, AI privacy, coach/client authorization,
audit logging, negative testing, detector validation.

Not covered, with reasons in §20: application runtime, production, any write-path test.

---

## 4 · PHI inventory

91 tables; **38 carry sensitive-looking columns**. The concentrations that matter:

| Table | Sensitive content | Live isolation result |
|---|---|---|
| `user_profiles` | **`parq_answers`** (PAR-Q medical history), `weight_kg`, `goal_weight_kg`, `transformation_photo_urls`, billing | **VERIFIED** — see §5 |
| `weekly_checkins` | mood, stress, sleep, energy, notes, weight | **VERIFIED** |
| `weight_logs`, `body_measurements` | weight, chest/waist | **VERIFIED** |
| `ai_memories` | auto-captured **injuries**, dislikes, constraints | **VERIFIED in QA — but see SEC-DRIFT-1** |
| `ai_profiles` | goals | same |
| `cycle_logs` / `cycle_settings` / `cycle_symptoms` | menstrual + reproductive health | **NOT DEMONSTRATED** — empty |
| `coach_notes`, `coach_video_responses`, `coach_exercise_media`, `messages` | coaching notes, voice, video, chat | **NOT DEMONSTRATED** — empty |

`exercise_modifications.condition` was a **false positive**: the table has no `user_id`
(`42703` live). It is an exercise catalogue, not personal data.

---

## 5 · RLS matrix (live, five authenticated identities)

Method: `select=*&limit=0` with `Prefer: count=exact` — returns a **count and zero rows**,
so no PHI value was ever retrieved.

### The decisive negative test — victim's profile row

| Identity | whole row | `parq_answers` | `weight_kg` | `transformation_photo_urls` |
|---|---|---|---|---|
| anon | `42501` | `42501` | `42501` | `42501` |
| **victim (owner)** | 1 | 1 | 1 | 1 |
| attacker (other client) | **0** | **0** | **0** | **0** |
| coach | **0** | **0** | **0** | **0** |
| admin | **0** | **0** | **0** | **0** |
| content_manager | **0** | **0** | **0** | **0** |

### What the coach result actually proves

The `coach` fixture **does** have a relationship with the victim — status **`cancelled`**.
So this is a **former-coach** test, and it is the strongest result in the audit:

> **A former coach is denied the former client's profile, PAR-Q, check-ins, weight logs,
> body measurements, AI memories and AI profile.** `is_active_coach_of()` returns `false`.
> **Revocation works. VERIFIED (live, negative).**

### The live `user_profiles` policy has four arms — only two were exercised

```sql
USING ( id = auth.uid()                    -- VERIFIED
     OR public.is_active_coach_of(id)      -- NOT TESTABLE (no active relationship)
     OR public.is_team_lead_of(id)         -- NOT TESTABLE (coach_team_members empty)
     OR public.hosts_event_for(id) )       -- NOT TESTABLE (event_registrations empty)
```

All three helpers returned `false` for every identity, and the tables that drive them hold
**0 rows**. **This is not a pass.** Static analysis of the two untested arms is in §10.

### Tables where every identity saw 0 rows — RLS **not demonstrated**

`cycle_settings`, `cycle_symptoms`, `cycle_logs`, `coach_notes`, `ai_conversations`,
`ai_insights`, `ai_goal_predictions`, `coach_video_responses`, `coach_exercise_media`,
`workout_feedback`, `weekly_feedback`, `action_items`, `coaching_calls`,
`client_nutrition_plans`, `workout_set_logs`, `workout_sessions`, `workout_logs`,
`notifications`, `messages`, `conversations`, `subscriptions`, `user_scores` — **22 tables.**

An empty table cannot demonstrate a boundary. These are **NOT TESTABLE** with current
fixtures, not verified.

### Readable by every authenticated identity (by design, assessed)

`community_posts` 10 · `post_comments` 5 · `custom_exercises` 621 · `events` 3 ·
`challenges` 3. Community and catalogue content. **These also serve as the positive
control proving the probe can see other users' rows when policy permits** — without
which every "0" above would be uninterpretable.

---

## 6 · RPC / SECURITY DEFINER results

123 functions, **97 SECURITY DEFINER**, **0 with `GRANT EXECUTE … TO anon`**.

| Function class | anon | attacker | coach | admin |
|---|---|---|---|---|
| `predict_client`, `assemble_weekly_review`, `resolve_exercise_media`, `evaluate_week` (UUID-accepting) | `42501` | **`42501`** | **`42501`** | 200 |
| `admin_platform_stats`, `admin_recent_users` | `42501` | **`42501`** | — | 200 |
| `decision_analytics`, `exercise_content_stats`, `intelligence_stats` | `42501` | **`42501`** | — | 200 |
| `is_admin` | `42501` | `false` | — | `true` |
| `is_active_coach_of` / `is_team_lead_of` / `hosts_event_for` | `42501` | `false` | `false` | `false` |

**No IDOR was reachable.** Every UUID-accepting function refuses a non-admin at the
EXECUTE-grant level — a stronger boundary than an internal check, because it never runs.

`marketplace_coaches()` returns 2 KB to any authenticated caller. Its `RETURNS TABLE`
limits output to name, avatar, title, tagline, bio, specialties, certifications, pricing,
rating, `plan_tier`, `is_featured`, `rank_score`. **No email, phone or PHI → FALSE
POSITIVE for PHI.** Minor: `plan_tier` and `rank_score` are business-internal and visible
to all clients (§18, OD-61).

VOLATILE functions were probed with **GET**, which PostgREST refuses with `405`/`404`
*without executing*. Nothing was mutated.

---

## 7 · Storage / media results

Probe: a fixed nonexistent object on the public path. `not_found` = the bucket **served**
the request → public. `Bucket not found` = private **or** absent.

| Bucket | Result | Verdict |
|---|---|---|
| **`coach-media`** | `not_found` | **PUBLIC — FAILED (SEC-VOICE-1 open, re-confirmed live)** |
| `avatars` | `not_found` | **PUBLIC** — path is `"$uid/avatar.$ext"`, predictable → §15 SEC-MEDIA-1 |
| `exercise-media` | `not_found` | PUBLIC — global exercise library, appropriate |
| `progress-photos`, `chat-media`, `messages` | `Bucket not found` | not publicly served |
| `__nope__` (control) | `Bucket not found` | **identical to the row above → private and absent are indistinguishable by this probe** (§20) |

**Note the ledger's discriminator text has changed**: the previous wave recorded
`NoSuchKey`/`NoSuchBucket`; the API now returns `not_found`/`Bucket not found`. The
partition is unchanged.

App-side: `createSignedUrl` is used for `progress-photos`, `chat-media` and coach voice
*display*. `getPublicUrl` remains at four sites — `coach_business_screen:134` (OD-58),
`personal_info_screen:134` (avatars), `custom_exercise_service:901/914` (exercise-media),
and **`custom_exercise_service:674` (coach voice → SEC-VOICE-2, §15).**

---

## 8 · N-07 / assessment privacy

| Question | Answer | Evidence |
|---|---|---|
| Does `get_client_assessment` exist live? | **NO** | `PGRST202` as coach |
| Has the N-07 migration been applied? | **NO** | same |
| Is base-table RLS still the only path? | **YES** | §5 — the four-arm `102` policy |
| Is assessment access logged? | **NO** | §11 |
| Can a former coach reach it? | **NO** | §5 — verified |
| Can an unassigned/team-lead/event-host reach it? | **NOT TESTABLE** | §5 |

**N-07 is not resolved.** SEC-PHI-3's ordering blocker is confirmed live: the Dart repoint
cannot precede a migration that has not been applied.

---

## 9 · AI privacy results

| | |
|---|---|
| **Provider** | **Anthropic** — `api.anthropic.com/v1/messages`; models `claude-haiku-4-5-20251001`, `claude-sonnet-4-6` |
| **Other egress** | `api.resend.com/emails`; `googleapis.com/youtube/v3/search` |
| **Data in** | goals, scores, workouts, nutrition, habits, **`cycle_logs`**, feedback, and `ai_memories` filtered to `kind='injury'` (`ai-coaching-engine:146–201`) |
| **Auto-capture** | `ai-coach:131–152` scans each message for *injur/hurt/sore/pain/allerg/…* and persists extracted facts as `ai_memories` rows with `kind:"injury"` |
| **Stored?** | Yes — `ai_memories`, identity-bound by `user_id` |
| **Access control** | Enforced live in QA; **not created by any migration — SEC-DRIFT-1** |
| **User visibility** | Yes — `_CoachingMemoryCard` (`ai_coach_screen:207`) lists memories |
| **User deletion** | **`onLongPress` only** — no label, affordance or confirmation; `deleteMemory` ends in `catch (_) {}` → §15 OD-60 |
| **Coach visibility** | Not via the client's `ai_memories` — no cross-user read observed |
| **Disclosed to the user?** | **NO — SEC-AI-1** |

---

## 10 · Authorization results (coach ↔ client)

| Boundary | Result |
|---|---|
| anon → any PHI table | **DENIED `42501`** (GRANT level, stronger than RLS) — VERIFIED |
| client → own record | ALLOWED — VERIFIED |
| client → another client | **DENIED** — VERIFIED |
| **former coach → former client** | **DENIED** — VERIFIED (status `cancelled`) |
| active coach → assigned client | **NOT TESTABLE** |
| team lead → member | **NOT TESTABLE** |
| event host/vendor → attendee | **NOT TESTABLE** |
| admin → another user's profile | **DENIED** (0 rows) — VERIFIED |
| content_manager → PHI | **DENIED** — VERIFIED |

### Static analysis of the two arms that cannot be tested

```sql
is_team_lead_of: EXISTS(SELECT 1 FROM coach_team_members
                        WHERE coach_id = auth.uid() AND member_id = target_user)
hosts_event_for: EXISTS(SELECT 1 FROM event_registrations r JOIN events e ON e.id = r.event_id
                        WHERE e.vendor_id = auth.uid() AND r.user_id = target_user)
```

Both grant the **entire `user_profiles` row**, `parq_answers` included.

- `is_team_lead_of` has **no status or active check** — unlike `is_active_coach_of`, which
  requires `status = 'active'`. There is no revocation condition at all.
- `hosts_event_for` means **an event vendor gains permanent access to an attendee's full
  profile, including medical history**, from a single registration. No time bound.

Migration `102` itself articulates the correct pattern for messaging — *"no contact,
medical, intake or billing column is involved — so it is served by a narrow view rather
than by a row grant on user_profiles"* — and then does not apply it to these two arms.
This corroborates **SEC-PHI-1** and sharpens it. Classification **C**.

---

## 11 · Audit logging results

Probed live as admin: `assessment_access_log`, `audit_log`, `phi_access_log`,
`access_log`, `security_events`, `audit_events`, `activity_log` — **all `PGRST205`
(absent).** Zero app-side or edge-function writes to any audit table.

| Action | Logged? |
|---|---|
| PHI / PAR-Q access | **NO** |
| Assessment access | **NO** |
| Coach assignment / termination | **NO** |
| Media access or deletion | **NO** |
| Admin access | **NO** |
| Role changes | **NO** |
| AI memory deletion | **NO** |

**A coach opening a client's PAR-Q leaves no record of actor, subject or time.**
SEC-PHI-AUDIT **FAILED**, re-confirmed live.

---

## 12 · Deletion / export / data-subject controls

The Account section contains exactly three rows: **Profile, Subscription, Connected Apps**
(`settings_screen:135–190`). There is **no deletion control and no export control anywhere
in the application**, and no backend deletion or export path in `supabase/functions/` or
`apps/api/`.

**The three documents disagree with each other:**

| Document | Claim | Reality |
|---|---|---|
| Privacy §5 **Deletion** | *"by emailing privacy@12circle.app … Deleting your account from inside the app is not available yet"* | **ACCURATE** |
| Privacy §5 **Access** | *"request a full export … from Profile → Settings → Account"* | **FALSE** — no such control |
| Terms §9 | *"delete your account at any time from Profile → Settings → Account"* | **FALSE** — no such control |
| Privacy §6 | *"If you delete your account, we purge personal data within 30 days"* | describes a path reachable only by email |
| Privacy §7 | *"row-level security policies on **all** database tables"* | **see SEC-PHI-5, §15** |

SEC-PHI-4 confirmed and refined. **OWNER DECISION** — remediation is legal copy or new
controls; neither is QA's to write.

---

## 13 · Runtime results

**NOT PERFORMED — ENVIRONMENT BLOCKED.** Exact causes:

- **Docker unavailable** — `Cannot connect to the Docker daemon`. This also blocked
  `supabase db dump --linked`, so **no schema read was possible**; every schema statement
  here is either live-probed behaviour or static migration analysis.
- **Disk at 1.3 GiB free (93 %)** — an emulator needs ~7.4 GiB and a build ~2.67 GiB.
- **No booted simulator or connected device.**

**Nothing in this report is marked RUNTIME_VERIFIED for the application.** The live
database results are labelled **LIVE-VERIFIED (QA database)**, which is a different and
narrower claim: it exercises PostgREST and RLS, not the Flutter client.

---

## 14 · Detector validation ("mutation testing" of this audit's instruments)

Every instrument was checked for the ability to produce a non-empty result before any
empty result was believed. **Five would have produced a wrong conclusion:**

| Instrument | Initial output | Fault | Corrected |
|---|---|---|---|
| SECURITY DEFINER scan | **0 functions** | regex stopped at `LANGUAGE`, which precedes `SECURITY DEFINER` | **97** |
| RLS matrix cells | `206` shown as an error | **206 Partial Content is success**; counts were hidden | counts recovered |
| `coach_client_relationships` | "no access" | `select=*` returns `42501` under **column-level** grants — it means "not every column" | granted columns readable |
| `search_path` audit | 53 unpinned | migration `118` runs a catch-all `pg_proc` loop that pins **all** of them | **false positive** |
| "tables never given RLS" | 15 | live probe **contradicts** it for `ai_memories`/`ai_profiles`; `which` was a parse artifact | → SEC-DRIFT-1 |

**Positive control:** `community_posts` (10 rows) and `custom_exercises` (621) are visible
to every identity, proving the probe *can* see rows owned by others. Without it, the 22
zero-row results would be indistinguishable from a broken probe.

**Negative control:** `__nope__`, a bucket that does not exist, returns the same response
as `progress-photos` — which is why §7 refuses to claim those buckets are "private".

---

## 15 · New discoveries

### SEC-AI-1 — health data is sent to an undisclosed sub-processor · **C**
Privacy §3 names Supabase, Expo and "selected analytics providers". Injuries, pain,
allergies, `cycle_logs`, weight and nutrition are transmitted to **`api.anthropic.com`**;
`api.resend.com` and the YouTube API also receive data. None appear in the policy.
§4's *"never share identifiable health data with third parties **for advertising**"* is
scoped to advertising and is therefore not contradicted — but the processor list is
incomplete. Remediation is disclosure and a processor agreement: **owner / legal.**

### SEC-DRIFT-1 — isolation exists in QA that exists in no migration · **B + E**
`ai_memories` and `ai_profiles` isolate per user live (victim 1 / attacker 0 / coach 0 /
admin 0, filtered to the victim's `user_id`). **Zero** `ENABLE ROW LEVEL SECURITY`,
`CREATE POLICY` or `GRANT` statements exist for them anywhere in `supabase/`.
Migration `118`'s standing guard only **`RAISE WARNING`s**; it does not enable anything.

Consequences if an environment is built from migrations alone:
- `ai_memories` — which stores auto-captured **injury** records — would be readable
  cross-user;
- `AiCoachService.deleteMemory` issues `delete().eq('id', id)` with **no `user_id`
  predicate**, so without RLS it is a cross-user **delete**.

I could not read `pg_class.relrowsecurity` (no grant; Docker blocked), so the *mechanism*
is unproven. What is established: **isolation is enforced in QA and is not created by any
migration in this repository.** Production impact is **NOT TESTABLE** — production access
is forbidden.

### SEC-VOICE-2 — the voice half of SEC-VOICE-1(a) was never done · **B**
`custom_exercise_service.dart:674` — `uploadCoachVoice` still ends
`return _db.storage.from('coach-media').getPublicUrl(path);`. The ledger records the Dart
prerequisite as **DONE**; only render-time signing was added. Every voice-note row
therefore holds a permanent unauthenticated URL, on a bucket **confirmed public today**.
Its sibling video path now stores an object path (SEC-VIDEO-1), so the two are
inconsistent — and voice is the one with a working player.

### SEC-PHI-5 — the Privacy Policy makes a security claim about the schema · **C**
Privacy §7: *"row-level security policies on **all** database tables."* 14 tables have no
RLS statement in any migration. Live behaviour contradicts the static reading for two of
them (SEC-DRIFT-1), and the remainder are empty and untestable. The claim cannot be
substantiated from this repository, and §7 also asserts TLS 1.3 and AES-256, which are
platform properties this audit cannot verify.

### SEC-MEDIA-1 — avatars are enumerable · **B (low)**
`avatars` is public and the path is `"$uid/avatar.$ext"`. Anyone holding a user's UUID can
fetch their photograph unauthenticated. Not demonstrated live (no avatar uploaded to a
fixture account), so **shape-confirmed, NOT TESTABLE** as behaviour.

### OD-60 — the only control over AI-held health facts is a hidden gesture · **H + C**
Deleting an `ai_memories` row — including an auto-captured injury — is `onLongPress` with
no label, no affordance and no confirmation, and `deleteMemory` ends in `catch (_) {}`, so
a failed deletion is silent.

---

## 16 · Previously recorded findings, re-verified

| Finding | Previous status | This wave | Evidence |
|---|---|---|---|
| anon least privilege | VERIFIED | **VERIFIED (live)** | `42501` on every PHI table |
| SEC-PHI-1 (wide `102` arms) | OWNER | **OPEN, sharpened** | §10 — no status check; full row to event vendors |
| SEC-PHI-2 (error disclosure) | RESOLVED | **holds** | 0 analyzer errors, ERR-G2 green |
| SEC-PHI-3 (N-07 repoint) | BLOCKED | **BLOCKED, confirmed live** | `PGRST202` |
| SEC-PHI-4 (data-subject controls) | OWNER | **confirmed + refined** | §12 — three documents disagree |
| SEC-PHI-AUDIT | FAILED | **FAILED (live)** | 7 table names, all `PGRST205` |
| SEC-VOICE-1 (bucket) | FAILED | **FAILED (live)** | `coach-media` public |
| SEC-VOICE-1(a) "Dart prerequisite DONE" | RESOLVED | **CORRECTED → SEC-VOICE-2** | §15 |
| SEC-VIDEO-1 | RESOLVED | **holds** | no `getPublicUrl` on the video path |
| OD-57 / OD-59 (write-only tables) | OWNER | **hold** | WO-G1 green |
| `invite_token` withholding (113) | applied | **VERIFIED, no regression** | `42501` for all five identities |

---

## 17 · False positives (recorded so they are not re-raised)

1. **53 SECURITY DEFINER functions "without `search_path`"** — migration `118` pins every
   unpinned function in `pg_proc` via a catch-all loop.
2. **`exercise_modifications.condition` as PHI** — the table has no `user_id` (`42703`);
   it is an exercise catalogue.
3. **`coach_client_relationships` "unreadable"** — column-level grants; `select=*` fails
   only because `invite_token`/`invite_id` are deliberately not granted.
4. **`admin_platform_stats` / `admin_recent_users` "granted to authenticated"** — the
   static grant is superseded; live, a non-admin gets `42501`.
5. **`marketplace_coaches` leaking PHI** — `RETURNS TABLE` limits it to marketing columns.
6. **`which` as a table** — a regex artifact in the RLS scan.

---

## 18 · Owner decisions

| ID | Decision required |
|---|---|
| **SEC-AI-1** | Disclose Anthropic/Resend/Google as processors; confirm a processor agreement covering health data |
| **SEC-PHI-1** | Narrow the team-lead and event-host arms to column-limited views; decide whether a team lead retains access after a member leaves |
| **SEC-PHI-4 / SEC-PHI-5** | Reconcile Terms §9, Privacy §5 Access, §6 and §7 with reality, or build the controls |
| **OD-57 / OD-59** | Build the video player and coach feedback view, or remove both features |
| **OD-58** | Whether `transformation_photo_urls` may stay public |
| **OD-60** | Whether a hidden long-press is an adequate control over health data |
| **OD-61** *(new)* | `marketplace_coaches` exposes each coach's `plan_tier` and `rank_score` to all authenticated users |

---

## 19 · Governance blockers

- Migration numbering: `132+` is assigned **at wave entry, never before**. No migration was
  written, numbered or applied. Two proposals remain AUTHORED and unnumbered.
- **SEC-DRIFT-1 cannot be closed without a migration**, which this phase may not create.
- Another workstream's files — `N07_IMPLEMENTATION_STATUS.md`,
  `proposed/N07_assessment_access.sql`, `supabase/tests/security/d09-assessment-access.mjs`,
  `FINAL_NEW_SCREEN_DESIGN_COMMISSION.md` — were **read as evidence and not modified**.
  The `wrk02-negative-control` worktree was **not touched**.

---

## 20 · Environmental blockers

| Blocker | Consequence | Reassess when |
|---|---|---|
| **Docker unavailable** | no `supabase db dump`; **no schema read**; RLS flags, policy list and grants unverifiable directly | Docker Desktop runs |
| **Disk 1.3 GiB free (93 %)** | no emulator, no device build, no app runtime | ≥ 10 GiB free |
| **`QA_SERVICE` absent** | cannot provision fixtures → the active-coach, team-lead and event-host arms and 22 empty tables stay untestable | key provided |
| **Production forbidden** | SEC-DRIFT-1's production impact unresolvable | explicit owner authorization |
| Public/private bucket probe | cannot distinguish private from absent | schema read available |

---

## 21 · Unresolved issues

`SEC-AI-1`, `SEC-DRIFT-1`, `SEC-VOICE-2`, `SEC-PHI-5`, `SEC-MEDIA-1`, `OD-60`, `OD-61`,
`SEC-PHI-1`, `SEC-PHI-3`, `SEC-PHI-4`, `SEC-PHI-AUDIT`, `SEC-VOICE-1(b)`, `OD-57`,
`OD-58`, `OD-59`, and the **22 tables whose RLS is undemonstrated**.

---

## 22 · Recommended remediation order

1. **SEC-DRIFT-1** — establish whether RLS on `ai_memories`/`ai_profiles` exists outside
   migrations. If it is drift, a migration must codify it before any environment is built
   from migrations alone. *Highest severity: injury data, and an unguarded delete-by-id.*
2. **SEC-VOICE-2** — store the object path, matching SEC-VIDEO-1. Cheap, no consumer break,
   and it is a prerequisite for privatising `coach-media`.
3. **SEC-VOICE-1(b)** — privatise `coach-media` once 2 lands. Blast radius is now only
   OD-58.
4. **SEC-AI-1** — disclosure and processor agreement (owner/legal; no code).
5. **SEC-PHI-AUDIT + N-07 + SEC-PHI-3** — one migration, then the Dart repoint.
6. **SEC-PHI-1** — column-limited views for the team-lead and event-host arms.
7. **SEC-PHI-4 / SEC-PHI-5** — reconcile the legal copy.
8. **QA infrastructure** — provide `QA_SERVICE` and seed fixtures, so the 22 undemonstrated
   tables and three untested arms become testable. *Without this, no future wave can do
   better than this one.*
9. OD-60, OD-61, SEC-MEDIA-1, OD-57/58/59.

---

## 23 · Evidence index

Every conclusion above is one of:

- **LIVE-VERIFIED (QA database)** — an HTTP status and row count from the QA PostgREST
  endpoint, authenticated as a named fixture identity, `limit=0` so no PHI value was ever
  returned. Sections 5, 6, 7, 8, 9, 10, 11.
- **STATIC** — a cited migration, function definition or source line. Sections 4, 10, 12, 15.
- **NOT TESTABLE** — the blocker is named in §20.

No conclusion rests on source code "looking correct": the RPC, RLS and storage sections
are all behavioural, and §14 records where an instrument was wrong before it was right.

---

## 24 · Final QA status

Discovery is exhausted against every channel available in this environment. The remaining
questions are not unexplored — each is pinned to a named governance or environmental
blocker in §19 and §20, with the condition for reassessment.

**SECURITY QA EXHAUSTED — OPEN FINDINGS REMAIN**

*No remediation was performed. No migration was created, numbered or applied. No
production system was contacted. This is not a claim of HIPAA compliance.*
