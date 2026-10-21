# PHI / HIPAA-relevant security ledger

Live evidence in this ledger was gathered **read-only** against the QA project
(`eyqtldjqpgpljlqvpowh`; production `nxdbooufqzkpslkcogxc` is refused by every probe).
Nothing was inserted, updated or deleted. No credential, token, email address or PHI
**value** appears here — only status codes, row counts, and whether a column is present.

Probe: `apps/mobile/tool/anon_least_privilege.py`.

> **This is a technical control assessment. It is not a HIPAA compliance certification.**

---

## 1 · Findings

### SEC-PHI-1 — a single policy serves both display data and PHI
| | |
|---|---|
| **Severity** | High (privacy) |
| **Area** | RLS · `user_profiles` |
| **Affected role** | `is_team_lead_of`, `hosts_event_for` |
| **Affected data** | `parq_answers`, `medical_conditions`, `has_injuries`, `injury_locations`, `injury_description`, `risk_score/level/flags`, `dietary_restrictions`, `food_allergies`, `sleep_hours`, `stress_level`, `occupation`, `date_of_birth` |
| **Access path** | `102_restrict_user_profiles.sql:165` — `USING (id = auth.uid() OR is_active_coach_of(id) OR is_team_lead_of(id) OR hosts_event_for(id))`. RLS grants **rows, not columns**, and no column-level `GRANT`/`REVOKE` on `user_profiles` exists in 131 migrations. |
| **Current behaviour** | Any principal satisfying any arm receives the entire row, PHI included. 102's own header says the last two arms exist to read **`email`** for a team roster and an attendee list. |
| **Expected** | A roster/attendee need is a display need. Clinical columns should follow the clinical relationship only. |
| **Evidence** | Policy text; `013_health_assessment.sql:5-23`; absence of column grants; `coach_team_members`, `event_registrations`, `events` all **exist live** (`42501`, not `PGRST205`). |
| **Status** | **PARTIAL — not proven exploitable.** No harness identity can satisfy either arm (see §3), so the arms could not be exercised. The consequence is certain from SQL semantics *if* an arm is satisfied; reachability is **BLOCKED**. |
| **Remediation** | Column-limited views for roster and attendee, mirroring what `102` already did for messaging and community, then drop the two arms. |
| **Governance blocker** | Migration number + owner sign-off. |
| **Attribution** | **Not novel.** Independently identified first in `docs/N07_IMPLEMENTATION_STATUS.md` §2, *"The authorization finding (owner decision required)"*, by another workstream. This ledger's contribution is the **live evidence** and the convergence of two independent analyses. |

### SEC-PHI-2 — the PAR-Q screen printed the database error into itself — **FIXED**
| | |
|---|---|
| **Severity** | Medium (information disclosure) |
| **Area** | Client · `client_detail_screen.dart` |
| **Access path** | `error: (e, _) => Text('Error: $e')` at `:132` and `:1620`, on the screen whose Assessment and PAR-Q tabs render a client's intake record. |
| **Current behaviour (was)** | A PostgREST/Postgres error carries table and column names, constraint text, and on a unique violation the conflicting **value**. |
| **Evidence** | Source; guard `test/unit/phi_screen_error_disclosure_guard_test.dart`; **3/3 mutations killed**. |
| **Status** | **RESOLVED** — replaced with the repository's own `Could not load [noun]` pattern. |
| **Residual — CLOSED, and the original count was wrong** | This row read *"five non-PHI sites still interpolate … and two in `admin_dashboard_screen.dart` which **parse** rather than display."* Both halves were wrong. A precise sweep found **38** sites across **26 files**, not five — including `womens_health_screen.dart` — and the admin card **both parsed and displayed**: its `denied` branch exists precisely because non-admins reach that screen, so every error that was not `42501` printed raw Postgres text to exactly that audience. **All 38 are now closed**, and the count is enforced by **ERR-G2** (`test/unit/raw_exception_display_guard_test.dart`) instead of asserted in prose. **5/5 mutations killed.** |
| **Why the first count was too low** | The original estimate was eyeballed from the PHI screens outward. The corrected sweep matches only **bare** interpolation (`$e`, `${e}`, `$error`) — an early version that also matched `${e.key}` and `${ex.name}` reported **59** for 38 real sites, so precision mattered in both directions. |
| **A guard flaw mutation testing caught** | ERR-G2's allowlist was first written **file-granular**. Planting `'Upload failed: $e'` in `progress_screen.dart` **SURVIVED**, because that file was listed for an unrelated storage path — and two of the five listed files, including `client_detail_screen.dart`, are PHI-adjacent. The allowlist is now **line-granular**: it exempts named code fragments, not files, and asserts each fragment still occurs so a stale exemption cannot silently widen. |

### SEC-PHI-3 — applying N-07 would not change what the shipped screen reads *(new)*
| | |
|---|---|
| **Severity** | Medium (remediation gap) |
| **Area** | Integration · `coach_ecosystem_provider.dart` ↔ `docs/proposed/N07_assessment_access.sql` |
| **Access path** | `clientDetailProvider` = `db.from('user_profiles').select('*').eq('id', clientId)` — the **base table**, gated only by 102's four arms. The proposal adds `get_client_assessment(uuid)`, a narrow RPC admitting only the active assigned coach and writing `assessment_access_log`. |
| **Current behaviour** | Applying the proposal adds a safe, audited door **beside** the wide one. The shipped Assessment/PAR-Q tabs keep reading the base table, so neither the narrowing nor the audit trail would take effect. |
| **Expected** | The assessment surface reads the audited path; the base-table read is removed or reduced. |
| **Evidence** | `coach_ecosystem_provider.dart:119-124`; proposal §"Instead it adds a dedicated, narrow read path"; the status doc's next-steps list does not include repointing the provider. |
| **Status** | **OPEN — REMEDIATION REQUIRED**, and it is *code*, not schema, so it is not migration-blocked. It is blocked on the migration landing first, since the RPC must exist before the Dart can call it. |
| **Governance blocker** | Ordering only: migration first, then the Dart repoint. |

### SEC-PHI-4 — the app promises data-subject controls it does not have *(new)*
| | |
|---|---|
| **Severity** | Medium (compliance-relevant accuracy; not a technical exposure) |
| **Area** | Client · policy screens |
| **Affected role** | every user |
| **Affected data** | the right of access, portability and erasure over their own record, PHI included |
| **Access path** | `terms_of_service_screen.dart` §9 — *"You may delete your account at any time from **Profile → Settings → Account**"*; `privacy_policy_screen.dart` §5 Access — *"You may request a full export of your data at any time from **Profile → Settings → Account**"* |
| **Current behaviour** | That screen's Account section holds exactly three rows — **Profile, Subscription, Connected Apps**. There is no deletion control and no export control; the app contains **zero** export controls anywhere. |
| **Expected** | Either the controls exist, or the copy describes the real channel. |
| **Evidence** | `settings_screen.dart:134-190`; a codebase-wide scan for an export control returns **0**. |
| **What is already correct** | Two of the three screens are accurate and say so plainly: `privacy_policy_screen.dart` §5 Deletion and `help_center_screen.dart` both state *"Deleting your account from inside the app is not available yet"* and give an email channel. **The app contradicts itself** — the Terms is the outlier. |
| **Status** | **OWNER DECISION.** Remediation is either building the controls or editing user-facing legal copy; neither is a QA decision. |
| **Guard** | `test/unit/data_rights_claims_guard_test.dart` (**RIGHTS-G1**), baseline **2**, 3/3 mutations killed. Pins the current state so a third promise cannot be added and the count must fall when one is honoured. |

### SEC-VOICE-1 — `coach-media` is a public bucket
| | |
|---|---|
| **Severity** | Medium–High (storage privacy) |
| **Affected data** | Coach **voice notes** and **video responses** addressed to a specific client |
| **Access path** | `036_client_plan_and_coach_media.sql:33` creates it `public = true`; `130_private_storage_buckets.sql` privatised `chat-media`, `messages`, `progress-photos` and **not** this one. Three `getPublicUrl()` call sites. |
| **Evidence (live, no credentials at all)** | `coach-media` → `NoSuchKey` (**the bucket served the request**); `progress-photos` / `chat-media` / `messages` → `NoSuchBucket`; nonexistent-bucket control → `NoSuchBucket`. `exercise-media` and `avatars` are also public. |
| **Status** | **FAILED — STORAGE PRIVACY** (bucket). **Deletion arm RESOLVED** — `clearCoachVoice()` now removes the object before clearing the row; 4/4 mutations killed. |
| **Remediation** | Two halves. **(a) Dart prerequisite — DONE:** voice playback now signs at render time via `signedCoachVoiceUrl()` (`createSignedUrl(path, 3600)`), so the migration can land without stopping existing notes from loading. Signing works on a public bucket, so this was safe to land first. **(b) Bucket — `docs/proposed/SEC_VOICE_1_coach_media_private.sql`, AUTHORED, unnumbered.** Still blocked. |
| **Governance blocker** | Migration number + owner sign-off; the read policy is an owner decision (a client must be able to play a note addressed to them). |
| **Remaining `getPublicUrl` sites — now resolved separately** | The other two were traced and are **not** the same case. `coach_video_response_screen.dart` → **SEC-VIDEO-1**, fixed (stores the object path). `coach_business_screen.dart:132` → **OD-58**, marketing photos plausibly meant to be public, owner's call. **Consequence for (b): the bucket can be privatised without breaking any coach-media read in the app** — voice signs, video has no reader, and only the marketplace photos are in question. That materially shrinks this migration's blast radius. |

### SEC-VIDEO-1 — coach video responses persisted a public URL
| | |
|---|---|
| **Severity** | Medium–High (storage privacy) |
| **Affected data** | A video of a coach discussing a **named** client, on the public `coach-media` bucket |
| **Access path** | `coach_video_response_screen.dart` (reachable: `client_detail_screen.dart:359` "Send Video Response") uploaded to `coach-videos/$coachUid/$clientId/$epochMillis.$ext` and called `getPublicUrl(path)`, persisting a **permanent, unauthenticated** URL into `coach_video_responses.video_url`. |
| **Status** | **RESOLVED (Dart).** Now stores the **object path**, to be signed at render time — the SEC-VOICE-1 treatment. Guard `VIDEO-G1` (`test/unit/coach_video_public_url_guard_test.dart`), **4/4 mutations killed**. |
| **Why it was safe to change** | **Nothing reads the column.** Verified: `coach_video_responses` is written at one site and read nowhere in `lib/`. So there was no consumer to regress — which is itself OD-57. |
| **Residual** | Rows written before this change still hold full public URLs. Whoever builds the player must accept both forms (`coachVoiceSigningPath` is the worked example). `VIDEO-G1`'s last test is a tripwire that fires with those instructions the moment a reader appears. |

### OD-57 — the video response feature is write-only (OWNER DECISION)
| | |
|---|---|
| **Type** | Design/feature gap — **not** something QA may invent |
| **Evidence** | A coach records and uploads a video, a row is written, and a notification is sent to the client reading *"Your coach recorded a personal video response for you. **Tap to watch.**"* There is **no player anywhere in the app**, and `notifications_screen.dart:157` makes a tap `markRead(n.id)` and navigate **nowhere — for every notification type**. The `coach_video` type has no route. |
| **Impact** | The coach believes the video was delivered; the client is told to tap to watch and cannot. The coach's work is unreachable, and PHI-adjacent media accumulates in storage with no legitimate consumer. |
| **Correction to the record** | `OD-25` left the check-in board's `Record` button inert citing QA_EVIDENCE §3ad: *"NOTHING in this app sends or renders a video — no capture path, no upload, no player."* **Two of those three clauses were false when written** — the capture (`ImagePicker().pickVideo`) and upload both exist, in a screen that even accepts the `checkinId` that board would pass. Only *no player* holds. The OD-25 **outcome survives** (wiring the button would add a second entrance to a dead end) but the stated reason did not, and the in-code comment has been corrected. |
| **Owner decision** | Build the player (and give `coach_video` a route), or remove the feature and its notification. Either is a product call. |

### OD-59 — `workout_feedback` is write-only, and the coach is told to tap (OWNER DECISION)
| | |
|---|---|
| **Type** | Design/feature gap — the second instance of OD-57's shape |
| **Evidence** | `active_workout_screen.dart:1966` inserts a client's rating, energy, difficulty and free-text **notes** into `workout_feedback`, then notifies the coach *"A client rated their workout n/5 — **tap to view**."* The table is **read nowhere** in `lib/`, and no coach surface renders it (the `rating` hits under `features/coach/` are marketplace **reviews**, a different table). A notification tap marks read and navigates nowhere. |
| **Impact** | The client writes notes to their coach that the coach cannot read. Rows about identifiable people accumulate with no surface that justifies them — a **data minimisation** problem as well as a dead feature. |
| **Owner decision** | Build the coach-side view, or stop writing the row and the notification. |

### The class, and what now guards it
Two confirmed write-only tables (`coach_video_responses`, `workout_feedback`), both
announced to a user with a tap promise the app cannot keep. Ratcheted by **WO-G1**
(`test/unit/write_only_table_guard_test.dart`), a **bidirectional shrinking allowlist** —
it fails if a third appears *and* if a listed one gains a reader. **4/4 mutations killed.**

> **False positives this sweep had to survive.** The first pass reported **four** tables.
> `accountability_pod_members` is read through PostgREST's **embedded resource** syntax
> (`select('*, accountability_pod_members!inner(...)')`, no `from()` of its own) and
> `weekly_feedback` through a **dynamic table name** (`avgOf('weekly_feedback', …)`).
> Both would have been filed as defects by a detector that only understood
> `from('x').select`. Separately, the notification **type** `'type': 'workout_feedback'`
> made a genuinely dead table read as live, which would have *hidden* OD-59 behind a
> passing test. Both confounds are handled, and asserted against, in the guard.

### OD-58 — `transformation_photo_urls` on a public bucket (OWNER DECISION)
| | |
|---|---|
| **Evidence** | `coach_business_screen.dart:132` uploads `coach-transformations/…` and appends to `user_profiles.transformation_photo_urls`, consumed by `coach_provider.dart:114` for the marketplace listing and rendered at `coach_business_screen.dart:208`. |
| **Assessment** | These are **marketing** photos shown to prospective clients who are not yet authenticated against that coach. Public may well be intended. Recorded as an owner decision rather than treated as a defect — but the subjects are identifiable clients, so consent for marketplace display is the owner's question to answer. |

### SEC-PHI-AUDIT — no PHI access logging exists
| | |
|---|---|
| **Severity** | High (auditability) |
| **Evidence** | `assessment_access_log`, `audit_log`, `phi_access_log` → all **ABSENT** live (`PGRST205`); **0** app-side writes to any audit table; no migration creates one. |
| **Current behaviour** | A coach opens a client's PAR-Q tab and nothing records actor, subject or time. |
| **Status** | ✅ **`VERIFIED_CLOSED` 2026-09-29.** Closed by migrations **140** (`assessment_access_log` + `get_client_assessment(uuid)`) and **141** (return-type repair), applied to QA under **OWNER DECISION OD-56 = A**. |
| **Governance blocker** | **CLEARED.** `OD-56 = A` given 2026-09-29. 140 was verified to be the next free number rather than assumed — authored migrations topped out at 139, the QA ledger read 139, and the declared frontier was 139. |
| **Closure evidence** | **FIXED IN CODE** — 140 + 141 committed. **FIXED ON QA** — ledger reads `141 \| 141 \| 141`; the table, its RLS, both policies and the function are verified in the live catalog. **VERIFIED LIVE** — `d09-assessment-access.mjs` **18/18 against QA**: the assigned coach receives 200 with 36 columns, an unassigned coach 403, `anon` 401, an **ended** relationship 403, the audit row carries `coach_id`, `client_id`, `event` and `accessed_at`, the subject reads their own log while a third party gets 0 rows, and `UPDATE`/`DELETE` on an audit row are **both 403** — append-only holds. **VERIFIED IN CI** — `d09` 18/18 inside `414/414 across 11 suites` in runs `36625112249` and `36626036076`, **plus** a tree-sensitive guard in `phase1_security_boundary_test.dart` proven to FAIL when 140/141 are absent, which is what §2's "fails against the pre-fix tree" requires and which `d09` alone cannot supply because its verdict comes from QA's state rather than the tree. |
| **Three defects found by executing it** | The suite had only ever been *authored* (`N07_IMPLEMENTATION_STATUS.md` §5: *"None of these has been executed"*), and running it first surfaced: (i) 140 declared `sleep_hours numeric` where the column is `text`, so the function raised **42804 on every call** — repaired by 141; (ii) `d09` called `signIn()` and **discarded the tokens**, sending `Authorization: Bearer coach`, so QA answered **401 to all eighteen assertions and seven scored that as a PASS**; (iii) all four of its fixture writes were **double-encoded** (`svc()` stringifies `body` itself), so the arrange silently did nothing. None was visible from source review. |

---

## 2 · RPC exposure matrix — anonymous role

**54 SECURITY DEFINER functions probed** with the anon key, **GET only**. PostgREST refuses
`GET` on a `VOLATILE` function with `405` *without executing it*, so no mutating function was
invoked.

| Result | Count |
|---|---|
| `404` — not exposed to anon | 41 |
| `401` — `42501`, no `EXECUTE` for anon | 13 |
| **executed / returned data** | **0** |

**No function carries an explicit `GRANT EXECUTE … TO anon`** anywhere in 131 migrations
(34 have explicit grants, 28 explicit revokes). → **VERIFIED SAFE.**

### PHI-touching functions — deep inspection

21 of the 56 read a PHI table. Those that accept a UUID and are not triggers:

| Function | Execute | Returns | RLS | Internal authz | Arbitrary UUID | Status |
|---|---|---|---|---|---|---|
| `is_coach_profile(uuid)` | `authenticated` (revoked from PUBLIC) | **`boolean`** only — `role = 'coach'` | bypassed (definer) | none | yes | **VERIFIED SAFE** — a bare predicate; `role` is already in `public_profiles` |
| `get_or_create_conversation(uuid)` | `authenticated` (revoked PUBLIC, anon) | `uuid` | bypassed | **binds participant 1 to `auth.uid()`**, raises `42501` unauthenticated, rejects self | yes, as *other* party only | **VERIFIED SAFE** — identity cannot be forged |
| `admin_recent_users(int)` | `authenticated` | 7 cols incl. `email` — **no PHI** | bypassed | **`is_admin()`, raises `42501`** | n/a | **VERIFIED SAFE** — tested both ways |
| `admin_platform_stats()` | `authenticated` | 13 aggregate cols | bypassed | **`is_admin()`, raises `42501`** | n/a | **VERIFIED SAFE** — tested both ways |
| `marketplace_coaches()` | `authenticated` | `RETURNS TABLE` 17 display cols — **0 PHI** | bypassed | none needed | n/a | **VERIFIED SAFE** — return type is the limiter |
| 12 × `trg_notify_*`, `handle_new_user`, `set_relationship_client_source` | — | `trigger` | — | — | — | **NOT RPC-CALLABLE** — PostgREST does not expose trigger functions |

**Positive/negative evidence** for the two `is_admin()`-gated functions (bodies read first and
confirmed to contain no `INSERT`/`UPDATE`/`DELETE`, so invocation cannot mutate):

```
admin_recent_users   anon 401 · attacker 403 · coach 403 · victim 403 · admin 200 rows=3 cols=7
admin_platform_stats anon 401 · attacker 403 · coach 403 · victim 403 · admin 200 rows=1 cols=13
```

Every denial is `42501`, raised **before** any data is returned. → **VERIFIED CONTROL.**

---

## 3 · Role-boundary results

| Boundary | Result |
|---|---|
| anon → any of 65 tables | **VERIFIED DENIED** — 0 readable, 64 × `42501` |
| anon → 3 RLS-bypassing views (`security_invoker = off`) | **VERIFIED DENIED** — `42501` |
| anon → 54 SECURITY DEFINER functions | **VERIFIED DENIED** |
| client → own PHI | **VERIFIED ALLOWED** — 6/6 PHI columns |
| client → another client's PHI | **VERIFIED DENIED** — 0 rows, both directions |
| client → another client's `weekly_checkins`, `cycle_symptoms`, `cycle_logs`, `progress_photo_logs`, `coach_notes` | **VERIFIED DENIED** — 0 rows each |
| unassigned coach → client PHI | **VERIFIED DENIED** — 0 rows |
| former coach (`cancelled`) → ex-client PHI | **VERIFIED DENIED** — 0 rows |
| the same, using `select('*')` **as the screen does** | **VERIFIED DENIED** — 0 rows |
| admin → a client's PHI | **VERIFIED DENIED** — 0 rows (own row only) |
| narrow view `public_profiles` → PHI | **VERIFIED DENIED** — 21 cols, **0 of 12** PHI; naming `parq_answers` fails `42703` |
| **active assigned coach → client PHI** | **BLOCKED** — no active relationship exists |
| **team lead → client PHI** | **BLOCKED** — `coach_team_members` empty for every identity |
| **event host / vendor → attendee PHI** | **BLOCKED** — 3 events exist, none owned by a harness identity |

Provisioning any of the last three requires a **write**, and creating identities requires the
service-role key. → **OD-51.**

---

## 4 · Other controls

| Control | Status | Evidence |
|---|---|---|
| Service-role key absent from client code | **VERIFIED** | 0 hits in `lib/` |
| PHI absent from `print`/`debugPrint`/`log` | **VERIFIED** | 0 hits |
| PHI absent from URLs / query parameters | **VERIFIED** | 0 hits |
| `SECURITY DEFINER` `search_path` pinned | **VERIFIED** | `116:77` catch-all `pg_proc` loop, re-run by `118` and `122` |
| Signed URLs for private media | **VERIFIED** | `createSignedUrl(path, 3600)` in 5 files for `progress-photos` / `chat-media` |
| Access revocation | **VERIFIED** | former coach denied, live |
| Storage object **enumeration** | **NOT TESTABLE** | every bucket lists `200 []` — but `progress_photo_logs` is `*/0`, i.e. QA holds no media, so the listing proves nothing |
| PHI access logging | **FAILED** | no table, no writes |
| `coach-media` privacy | **FAILED** | public, live-verified |
| Third-party analytics / telemetry | **VERIFIED** | **no SDK in `pubspec.yaml`** — no firebase_analytics, amplitude, mixpanel, posthog, sentry, segment or datadog. Nothing is shipped to a vendor, so there is no analytics egress path for PHI at all |
| Generated reports / screenshots | **VERIFIED** | no PDF generation, no `RenderRepaintBoundary`/`toImage()` capture. The only "screenshot" references are a code comment and an instruction telling a user to screenshot their own event ticket |
| Crash/error reporting egress | **VERIFIED today · PARTIAL by design** | `reportError` routes to a `FailureSink` that is **test-only until PD-A24 names a vendor**; `_defaultSink` calls `debugPrint` **only under `kDebugMode`**, so a release build emits nothing. Of 16 call sites, **2** pass a `context` map and both carry scoring metadata (`category`, `action`) — no PHI. **Precondition for the future:** the `error` object itself is passed from data-layer sites (`CheckinService`, `MessagingService`), and a Postgres error can carry column names and values. Re-audit these payloads **before** a real sink is installed. |
| Account deletion / data export paths | **FAILED** | promised at a path that has no such control — SEC-PHI-4 |
| Notification payload contents | **VERIFIED** | 0 PHI references in any notification body |
| Local persistence / cache of PHI | **VERIFIED** | 0 PHI written to SharedPreferences/Hive/sqflite |

---

## 4b · Classes swept this wave, with their negative results

Recorded because a sweep that finds nothing is only worth something if the detector was
shown capable of finding something. Each of these was validated against a planted or
known instance **before** its result was accepted.

| Class | Result | How the detector was proven non-vacuous |
|---|---|---|
| `setState` after `await` with no `mounted` guard | **54 sites fixed** — LIFE-G1, 4/4 mutations killed | The first, line-based sweep said 135; brace-scoping each `async` body gave 54. The detector asserts it still fires on an unguarded fixture and stays silent on a guarded one. |
| Raw exception shown to a user | **38 sites fixed** — ERR-G2, 5/5 mutations killed | An early version matching `${e.key}` reported 59 for 38 real. Mutation testing then found the guard's allowlist was file-granular and blind inside listed files. |
| Tables written and never read | **2 confirmed** (OD-57, OD-59) — WO-G1, 4/4 killed | The first pass reported 4; two were reads the detector could not see (embedded resource, dynamic table name). |
| App reads a relation no migration creates | **0 new** | Reproduced **exactly** the set QA Workstream I already registers (`checkins`/I-CHK-01, `coach_tips`/I-LEG-03) plus one storage-bucket false positive. Independent corroboration; **no competing guard added.** |
| Controller fields never disposed | **0 genuine** | First regex required an explicit type and found **1** field in the whole app — vacuous. Corrected to match inference (89 fields), which flagged 6; all 6 are disposed in a `for (final c in [...]) c.dispose()` loop. |
| `catch` → bare default (`[]`/`null`/`0`/`false`) | **101 sites — NOT remediated, stays OD-8** | Converting these requires an error state in the UI that mostly does not exist, so it is a product decision, not a QA one. An attempt to isolate the provable subset — the A-G6 shape, a dead `error:` arm over a swallowing service — returned **0**, and the two candidates it did surface were false (`getTotalVolumeLifted`'s `return 0` is the signed-out answer; `getCheckinStreak`'s only match was inside a doc comment quoting the old code). Stated as *not found by this method*, not as *none exist*. |

---

## 5 · Governance

Nothing in this ledger was remediated in schema. Two proposals are **AUTHORED and
unnumbered** — `docs/proposed/SEC_VOICE_1_coach_media_private.sql` and the pre-existing
`docs/proposed/N07_assessment_access.sql`. `docs/MASTER_REMEDIATION_WAVES.md` reserves
**132+** for *"assigned at wave entry, never before"*.

Files owned by the other workstream — `docs/N07_IMPLEMENTATION_STATUS.md`,
`docs/proposed/N07_assessment_access.sql`, `supabase/tests/security/d09-assessment-access.mjs`,
`docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md` — were **read as evidence and not modified**.
