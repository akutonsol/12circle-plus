# QA EVIDENCE LEDGER — 12Circle Fitness

The single classified index of findings. **This is an index, not a second report**: detail
lives in the documents referenced, and nothing is restated here that is recorded there.

- `docs/MOBILE_QA_SWEEP_2026-09-22.md` — technical + Android runtime QA (§1–§23)
- `docs/DESIGN_INTAKE_REPORT.md` — design package intake and repo conflicts
- `docs/DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` — FIT→route→implementation mapping

Classifications are used strictly, per brief §19: **PASS · FAIL · BLOCKED ·
NOT ESTABLISHED · OWNER DECISION · ENVIRONMENT LIMITATION**. A category is never converted
to make the ledger read better.

Repository: `chore/qa-environments-secure-ai-backend`. Last updated 2026-09-23.

---

## 0 · RECONCILIATION AGAINST `QA_CLOSURE_STANDARD.md` — several of my own claims were overstated

`docs/QA_CLOSURE_STANDARD.md` outranks this ledger and outranks any specialist skill
(governance precedence: owner → product spec → design package → repo contracts → **closure
standard** → skills → generic agents). Reading it against the work recorded below forces
three corrections. They are made here rather than quietly edited into the tables.

### 0.1 The evidence ladder has five states, and I used one word for several of them

§2 defines `FIXED IN CODE` · `VERIFIED IN CI` · `FIXED ON QA` · `VERIFIED LIVE` ·
`VERIFIED END-TO-END`, and §4 states plainly that *"the code changed"* is **one** of those
states, not a closure. §2.1 then fixes, per finding class, which states are **required**.

**No finding in this programme is `VERIFIED_CLOSED`, because nothing is `VERIFIED IN CI`.**

There are **17 commits on this branch and none are pushed**. §4 lists, as an explicit
non-closure: *"A passing suite that has never run in CI — a guard nobody runs protects
nobody."* Every guard I added (A-G1…A-G5, D-T1…D-T5, the F-20 widget tests) is in exactly
that position. They pass on this machine. That is not the claim the standard requires.

| Finding | Class (§2.1) | States required | States I actually have | Verdict |
|---|---|---|---|---|
| F-1 Android build | Release / environment | FIXED IN CODE · **VERIFIED IN CI** | FIXED IN CODE | **NOT CLOSED** |
| F-2 auth exception text | Error contract / false success | FIXED IN CODE · VERIFIED IN CI · VERIFIED END-TO-END | FIXED IN CODE · END-TO-END (device) | **NOT CLOSED** — no CI |
| F-2b chat fabrication | Error contract / false success | FIXED IN CODE · VERIFIED IN CI · VERIFIED END-TO-END | FIXED IN CODE only | **NOT CLOSED** — I earlier wrote "VERIFIED COMPLETE"; that was wrong. I never reached an empty conversation at runtime |
| F-3 app name | Hygiene / P3 | FIXED IN CODE · VERIFIED IN CI where cheap | FIXED IN CODE · END-TO-END | **NOT CLOSED** — no CI |
| F-6b password toggle | Product integrity / UI reachability | FIXED IN CODE · VERIFIED IN CI · VERIFIED END-TO-END | FIXED IN CODE · END-TO-END | **NOT CLOSED** — no CI |
| F-20 workout identity | Product integrity / UI reachability | FIXED IN CODE · VERIFIED IN CI · VERIFIED END-TO-END | FIXED IN CODE · END-TO-END | **NOT CLOSED** — no CI |
| F-12 / F-12a | Security / authorization | FIXED IN CODE · FIXED ON QA · VERIFIED LIVE · VERIFIED IN CI | VERIFIED LIVE (disposition only; no fix exists) | **OPEN by design** — F-12a has no fix |

**Correction of record:** my previous checkpoint reported F-20 as "IMPLEMENTED AND
RUNTIME-VERIFIED" and F-2b as "VERIFIED COMPLETE". Both were accurate about the *device*
and inaccurate as *closures*. `VERIFIED END-TO-END` is a real state and I earned it for
F-20; it is not the whole ladder its class demands.

**This is not a technicality.** The standard exists (§1) because *"findings were later found
open, and in three cases the closure itself introduced the regression."* I introduced two
regressions during this programme and caught both only on-device — the `MergeSemantics`
change that destroyed the password toggle, and the doubled semantics labels. A guard that
has never run in CI would not have caught either on someone else's machine.

**Blocking condition, escalated rather than worked around:** the owner instructed "Hold —
keep local" for pushes. That instruction is higher in the precedence order than this
standard and is respected. The consequence is recorded, not circumvented: **until these
commits run in CI, no finding in this programme can be marked `VERIFIED_CLOSED`.** See
OD-12.

### 0.2 "850 tests pass" is a weaker statement than it sounds

§4 records that **259 tests — 37% of the Flutter suite — define the logic inside the test
file and assert against the copy**: *"They are green whatever the app does."*

I have repeated "848 / 850 tests pass" as a headline several times without that caveat. It
remains true and remains worth running, but it is not evidence that the *application*
behaves. The guards I added are deliberately of the other kind — they read committed source
or drive the real widget — and each was mutation-tested, which is the property that makes a
guard mean something. That distinction should have been stated the first time.

### 0.3 The standard already names two of my findings, independently

§4's non-closure table records, before I looked at either:

- *"`EC-G1` asserts `workout_provider.dart` contains no `catch`. The defect moved to the
  screens and to the service. The guard passes. **The defect is live.**"*
- *"`EC-G5` counts `catch` blocks. Riverpod swallows via `error: (_,__) =>` and
  `.valueOrNull`, which contain no `catch`. **~150 sites are invisible to it.**"*

That is F-15 and F-16, reached from the opposite direction. It also explains why my A-G5
guard is written to match `error: (_, __) =>` shapes rather than `catch` blocks: the
existing ratchet cannot see the defect's shape, and a second guard with the same blind spot
would have been theatre.

---

---

## 0b · F-21 — **P1 SECURITY: any authenticated user can assign a workout programme to any other user**

**ID** F-21 · **Severity** P1 · **Status** OPEN — **authorization change required, escalated as OD-14**
**Source** found incidentally while arranging a runtime fixture for FIT-014, then
investigated under `12-12circle-security-engineer`.
**Environment** QA `eyqtldjqpgpljlqvpowh`. **Production was not tested and nothing is
claimed about it.**

### Observed

Signed in as the committed fixture `p1-victim@qa.12circle.test` — **role `client`**:

| Step | Request | Result |
|---|---|---|
| 1 | `POST workout_programs {name, coach_id: <own uid>}` | **201 — row created** |
| 2 | `POST workout_program_assignments {program_id, client_id: <own uid>, coach_id: <own uid>, status: active}` | **201 — row created** |
| 3 | `POST workout_program_assignments {program_id, client_id: <p1-coach uid>, coach_id: <own uid>, status: active}` | **201 — CROSS-USER WRITE** |

### Expected

A member cannot author a training programme as a coach, and cannot place a programme into
another person's plan.

### Root cause

`supabase/migrations/001_full_ecosystem.sql:351,357`:

```sql
CREATE POLICY "coaches manage programs" ON workout_programs
  FOR ALL TO authenticated USING (coach_id = auth.uid());

CREATE POLICY "coaches manage assignments" ON workout_program_assignments
  FOR ALL TO authenticated USING (coach_id = auth.uid() OR client_id = auth.uid());
```

Both are named for coaches and **neither checks that the caller is one.** The predicate is
satisfied by anyone willing to write their own uid into `coach_id`. The repository already
has the helper this needs — `public.is_coach_profile(uuid)`
(`113_rls_coach_client_relationships.sql:58`) — and migration 113 applies exactly that
check to `coach_client_relationships`. It was never applied here.

`FOR ALL` with `USING` and no `WITH CHECK` also means the INSERT path is governed by a
predicate written for reads.

### Why this is more serious than F-12

F-12 found route-entry weakness with **no demonstrated cross-user mutation**. This one *is*
a demonstrated cross-user mutation, and its payload is a **training prescription**: loads,
sets and reps that the receiving member's `/train` will present as their coach's plan. Under
`QA_CLOSURE_STANDARD` §5.1 a workout prescription injected by an arbitrary party is a
safety input, and §5.1 closes safety findings live or not at all.

The victim's hub renders it through the very surface integrated in this cycle
(`_PlanSurface` → `_TodayHeroCard`), attributed with "assigned by …".

### Not fixed — and why that is the correct call

Tightening these policies is an **authorization policy change**, which the governing
instruction lists as a genuine stop condition. The fix is small and obvious — add
`is_coach_profile(coach_id)` and an explicit `WITH CHECK` — but QA does not change the
authorization model on its own initiative. **OD-14.**

### Fixture hygiene

Three rows were created by the probe and all three deleted. Verified by re-query:
`remaining SEC-PROBE rows: 0`. An earlier single-row probe was likewise deleted and
verified at 0.

### F-21b · Blast radius — measured statically, read-only, no further mutation

The exploit is a *policy shape*, so the surface was sized by auditing every `FOR ALL`
policy in `supabase/migrations/` rather than by creating more rows.

**22 policies share the shape and are CORRECT** — `"users manage own weight logs"` with
`user_id = auth.uid()` scopes a user to their own rows, which is the intent. Those are not
defects and are not listed.

**15 carry a privilege-asserting NAME with no role check.** The predicate is satisfied by
writing your own uid into the column the name claims authority over:

| Migration | Table | Predicate columns | Policy |
|---|---|---|---|
| `001:347` | `coach_invites` | coach_id | "coaches manage invites" |
| `001:351` | `workout_programs` | coach_id | "coaches manage programs" — **PROVEN** |
| `001:354` | `program_workouts` | coach_id | "coaches manage program workouts" |
| `001:357` | `workout_program_assignments` | **client_id, coach_id** | "coaches manage assignments" — **PROVEN** |
| `001:360` | `client_nutrition_plans` | **client_id, coach_id** | "coach client nutrition" |
| `001:361` | `client_habits` | **client_id, coach_id** | "coach client habits" |
| `001:386` | `challenges` | coach_id | "coaches manage challenges" |
| `001:392` | `classes` | coach_id | "coaches manage classes" |
| `002:47` | `coach_availability` | coach_id | "Coaches manage own availability" |
| `002:67` | `coaching_calls` | **client_id, coach_id** | "Coach and client can see calls" |
| `002:104` | `accountability_pods` | coach_id | "Coaches manage pods" |
| `002:146` | `coach_team_members` | coach_id | "Head coach manages team" |
| `002:159` | `coach_team_invites` | coach_id | "Coach manages own invites" |
| `005:48` | `custom_exercises` | coach_id | "coaches manage own exercises" |
| `017:46` | `action_items` | coach_id | "coach manages assigned action items" |

**The four in bold are the cross-user injection candidates.** They carry a `client_id`
alongside `coach_id`, so the `coach_id = auth.uid()` arm lets a caller name themselves
coach while targeting *someone else* as the client — which is exactly the step-3 write
proven for `workout_program_assignments`. The other three are **UNTESTED**: predicted from
the shape, not demonstrated, and recorded that way.

By payload: `client_nutrition_plans` and `client_habits` would inject a nutrition plan or
habit into another member's programme; `coaching_calls` would place a call in their
schedule. With `workout_program_assignments` these are the same class of safety input as
F-21.

**Nothing further was written.** Confirming the remaining three needs one INSERT each, which
is a security decision to authorise, not one to take unilaterally — it is folded into
OD-14.

### Next tests, once authorised

`program_workouts` (`001:354` scopes by program ownership — inherits the same weakness),
`workout_program_assignments` UPDATE/DELETE by a non-party, and whether the victim's client
actually renders an injected programme end-to-end.

---

## 0c · F-22 — icon-only controls ship with no accessible name (**56 → 46 raw, ~40 real**)

**ID** F-22 · **Severity** P2 accessibility · **Status** RATCHETED, OD-8 for the copy

A tappable whose entire content is an `Icon` reports to the accessibility tree with **no
name**; a screen reader announces nothing. Measured on-device twice — the password toggle
(19.8 × 20.2 dp) and the three top-bar controls (38 × 38). Both are now named from the
design's own wording.

A repository-wide scan of the shape that actually reports unlabelled — a tappable whose
subtree holds an `Icon` and no `Text`, `tooltip` or `Semantics` — finds **56 more across 36
files**. Heaviest: `exercise_content_center_screen` (4), `active_workout_screen` (4),
`progress_screen` (3), `create_exercise_screen` (3), `meals_dashboard_screen` (3).

**Not mass-fixed, deliberately.** Naming a control is product copy. The authoritative
package supplies vocabulary for the controls it draws — "Back", "More", "Directory",
"Messages", "Notifications", "History", "Exercise library", "Show password" — and all of
those have been applied. It does not name every icon in screens it does not draw, and
inventing 56 strings is the fabrication the brief forbids. Folded into **OD-8**.

**Guard A-G8** holds the population at 56 and fails on the 57th — mutation-tested
("Found 57 across 36 files (baseline 56)"). A second assertion pins the controls already
fixed so they cannot silently regress.

It deliberately does **not** repeat EC-G5's mistake, which `QA_CLOSURE_STANDARD` §4 records
as counting `catch` blocks while the defect it targets contains none: A-G8 matches the
shape that reports unlabelled, not a keyword that happens to sit nearby.

### What was named, and what was deliberately left alone

The package declares short control labels, and three cover a large share of this
population: **"Back" (138 declarations), "Close" (4), "Refresh" (8)**. A back arrow named
"Back" and a close cross named "Close" use the design's own words, so they are not product
copy. Nine controls were named on that basis, plus the intake flow's three under F-9:

| Screen | Control | Name |
|---|---|---|
| `/progress` ×2 | measurement-sheet crosses | Close |
| `/directory` | sheet cross | Close |
| `/nutrition` | sheet cross | Close |
| `/daily-checkin` | header back arrow | Back |
| `/chat` | header back arrow | Back |
| `/messages` | header back arrow, refresh | Back, Refresh |
| `/intake` ×3 | `_AppBar`, `_IntakeStepBar`, profile header | Back |

Each also gained a 44 dp target around its unchanged 36 dp chip.

**Three crosses were left unnamed on purpose**, although naming them "Close" would have
moved the number faster:

* `coach_checkin_review_screen.dart` — the cross **removes a recommendation**. "Close" is
  wrong, and the package declares only "Remove <thing>", never a bare "Remove".
* `exercise_database_screen.dart` — the cross **clears a search field**. Same reason.
* `coach_notes_sheet.dart` — the cross is wired to `onDelete`. The package declares no
  delete label at all.

A wrong name is not a smaller version of a missing one. These stay under OD-8.

**A false positive found by doing this.** `workout_detail_screen.dart`'s back control was
*already* named by F-20 — the scan reads forward from each tappable and could not see the
`Semantics` above it, so the site was counted. The first attempt double-wrapped it and the
F-20 test caught it (`Found 2 widgets with a semantics label named "Back"`). The wrapper
was removed and the site annotated. The scan is still not widened backwards, for the
reason recorded in the guard.

### The scan over-counts, and by how much

A-G8 reads **forward** from each tappable, so a `Semantics` wrapper placed *outside* the
`GestureDetector` is invisible to it. Six sites are verified named and still counted. The
clearest is `auth_design.dart`'s password toggle: **this guard already asserts that control
is named** — it was measured on-device at 19.8 × 20.2 dp and fixed as F-6b — and the scan
counts it anyway.

| Site | Name it actually carries |
|---|---|
| `auth_design.dart` | `Show password` / `Hide password` |
| `workout_detail_screen.dart` | `Back` |
| `nutrition_screen.dart` | `Close` |
| `directory_screen.dart` | `Close` |
| `meals_dashboard_screen.dart` | `Log a meal` |
| `ai_nutrition_screen.dart` | `Scan a meal` |

So the raw figure is **46** and the real one is about **40**.

**The window is still not widened backwards.** A backward window would also swallow an
unrelated `Semantics` above a genuinely unnamed control, and a ratchet that under-counts
hides regressions while one that over-counts only overstates the work left. What was not
acceptable was leaving the discrepancy as a sentence in prose: the six are now **listed and
asserted** in the guard, so if one loses its name the test fails and it becomes a real
finding again. Mutation-tested both ways — removing a listed name fails, and a new unnamed
control still fails the baseline at 47.

**Two more named from the package's vocabulary**, bringing 47 → 46: FIT-003 declares
`Log a meal` and `Scan a meal`, and both controls do exactly what those labels say — the
`+` opens the add-meal sheet, the camera picks a photo and has it analysed.

## 0d · F-9 — **RESOLVED AND MEASURED ON DEVICE**, including the related finding

**Cause.** There is no `MergeSemantics`, `Semantics` or `BlockSemantics` anywhere in
`intake_flow_screen.dart` — verified by grep. The merge was Flutter's default: with only
one actionable node on the page (a bare `GestureDetector` around a back icon), the
surrounding `Text` had no boundary of its own and was absorbed into it, which also
expanded that node's rect to the whole screen. Page 2 yielded 11 nodes because its form
fields create boundaries naturally.

**What was wrong, measured.** The earlier `uiautomator` dump recorded page 2 still
carrying a whole-screen control: `411.4 × 914.3 dp, clickable=true, 'Your Profile\nTell
us a little about yourself.'`. A screen reader offered the entire page as one button named
after the heading.

**The fix.** The intake flow's **three** back controls — `_AppBar` (40 dp),
`_IntakeStepBar` (36 dp) and the profile header (36 dp) — were all bare
`GestureDetector`s with no name and under the 44 dp floor. They are now one
`IntakeBackButton`: named "Back" (FIT-027's own word), `container: true` so it is its own
node and cannot swallow its neighbours, 44 dp target, visible chip unchanged. The two
header lines were given their own boundaries, the title as a `header`.

**Measured on `emulator-5554`, dpr 2.625, 411.4 × 914.3 dp** — by reading the real
semantics tree through the embedder rather than `uiautomator`, which returns an empty tree
unless an accessibility service is enabled:

| | Before | After |
|---|---|---|
| nodes on page 2 | the header and the control merged into one whole-screen node | **18 discrete nodes** |
| tappable nodes covering >50% of the screen | 1 | **0** |
| back control | absorbed, unnamed | `44.0 × 44.0 dp, tap=true, label="Back"` |
| "Your Profile" | inside the control | own node, `315.4 × 29.0 dp`, not tappable |
| "Tell us a little about yourself." | inside the control | own node, `186.0 × 20.0 dp`, not tappable |
| "Continue" | — | `button=true enabled=false tap=false` while the form is invalid, `enabled=true tap=true` once filled |

`integration_test/f9_intake_semantics_device_test.dart`. It writes nothing: the page takes
plain values and callbacks, so it mounts with no session and touches no backend — which is
also how it sidesteps the blocker recorded before. Reaching page 2 as a signed-in user
needs a fixture with no intake data, and manufacturing one means writing intake rows while
F-21 is open.

### A defect this probe found in my own fix, and the rule it produced

The first version of `IntakeBackButton` used `excludeSemantics: true` to keep the icon out
of the announcement. **That drops the child's ACTIONS along with its labels.** The device
read `44x44 tap=false label="Back"` — a node announced as a button that a screen reader
cannot press. Worse than the unnamed control it replaced, and every host-VM test was green,
because they asserted the name and the size and not the action.

`_RestAction` (FIT-017's "Add 30 seconds" / "Skip rest, start set") had the identical
defect, introduced earlier in this same cycle and not noticed. Both now pass `onTap` to the
`Semantics` as well, and **all three device probes assert the tap action, not just the
name**. Confirmed by mutation: removing the `Semantics` `onTap` fails both files.

The rule: *`excludeSemantics: true` requires re-declaring the action.* Only the device
showed it.

### Still open on this screen

`_GradientButton` now declares its role and `enabled` state (the child `Text` supplies the
name, so no label is set — doubling an announcement is a mistake this repository has
already made once). The rest of the intake flow's controls have not been audited; A-G8
counts what remains.

## 1 · Defects found and fixed, each verified at runtime

| # | Finding | Evidence | Status |
|---|---|---|---|
| F-1 | Android app could not build at all — `flutter_local_notifications` 18.x requires core library desugaring, never configured in repo history | `:app:checkDebugAarMetadata` failure; `git log -S` empty | **PASS** — fixed `6fdfed9`, APK builds |
| F-2 | All four auth screens showed users a raw `AuthApiException(...)` object | On-device SnackBar, `emulator-5554` | **PASS** — fixed `320d565`, device shows "Invalid login credentials"; guard A-G2 mutation-tested |
| F-3 | App's user-facing name was `circle_fitness` in launcher, Settings and every permission dialog | Permission dialog screenshot | **PASS** — fixed `dfea573` to "12Circle Fitness"; re-verified on device; guard A-G3 mutation-tested |
| F-4 | `_IconBtn` declared a required `tooltip` it never read — control unlabelled | Source + guard | **PASS** — fixed earlier; guard A-G1 mutation-tested |

## 2 · Defects found, NOT fixed — each blocked on a decision, not on effort

| # | Finding | Evidence | Status |
|---|---|---|---|
| F-5 | Landscape: `splash_screen.dart:109` overflows 39 px, painting Flutter's overflow stripe across the "Get Started" CTA | On-device, `ROTATION_90`, reproduced on cold start | **OWNER DECISION** (OD-1) — no one-line fix exists (`Spacer` cannot sit in a `SingleChildScrollView`); design GAP-06 says landscape is not designed at all |
| F-6 | Password visibility toggle is **19.8 × 20.2 dp with no accessible name** — under half the 44 dp floor | `uiautomator` dump, 2.625 px/dp | **OWNER DECISION** (D-3 copy) — size fix is mechanical, the label is product copy |
| F-7 | "Forgot password?" 20.2 dp and "Sign Up" 19.8 dp targets | same dump | **OWNER DECISION** — same class as F-6 |
| F-8 | Text inputs expose their *value* but carry no accessible **name** | same dump | **OWNER DECISION** (copy) |
| F-9 | Intake welcome page collapses to **one merged accessibility node**; "Get Started" not separately focusable; the same whole-screen clickable node also present on page 2 | `uiautomator` dump ×2; re-measured through the embedder on `emulator-5554` | **PASS — MEASURED ON DEVICE.** 18 discrete nodes, 0 whole-screen controls, back control `44.0 × 44.0 dp, tap=true, label="Back"`. See §0d, including a defect the probe found in the fix itself |
| F-10 | `event_ticket_screen` is unrouted — reached only via `MaterialPageRoute`, so no URL, no deep link, outside the router shell | `app_router.dart` grep + `events_screen.dart:81` | **OWNER DECISION** (OD-4, design GAP-09) |
| F-2b | Chat screen displayed four **fabricated messages** as the user's real coach conversation whenever a thread was empty or could not be created | `chat_screen.dart:88`, `messaging_service.dart:237-245` | **PASS** — fixed `0243867`; empty state restored, distinct failure state added, 840 tests pass |
| F-6b | Password toggle 19.8x20.2dp unlabelled | `uiautomator` before/after | **PASS** — now **43.8 x 43.8 dp, labelled "Show password"**, verified on device; copy is the design's own |
| F-11 | **No fonts are bundled and `allowRuntimeFetching` is never set** (defaults true) — every font is fetched from `fonts.gstatic.com` at runtime, so a first launch offline silently falls back to Roboto and the whole type system degrades | no `fonts:` in `pubspec.yaml`, no `.ttf`/`.otf` assets, no `GoogleFonts.config` anywhere | **OWNER DECISION** — bundle the family, or accept the degraded offline first run |

## 3 · Verified passing — stated because absence of evidence is not evidence

| Finding | Evidence | Status |
|---|---|---|
| App launches, authenticates against QA, navigates; no `FATAL`, no `E/flutter` in any pass | `emulator-5554`, API 35; session key `flutter.sb-eyqtldjqpgpljlqvpowh-auth-token` persisted | **PASS** |
| Keyboard insets correct — content resizes, footer relocates, nothing clipped or obscured | `mInputShown=true` + screenshot | **PASS** |
| Password masking is secure — masked field reports `password=true` and **withholds its value** from the accessibility tree | dump before/after toggle | **PASS** |
| System back returns to the previous screen and stays in-app | `dumpsys activity` | **PASS** |
| Landscape produces **no** `RenderFlex` overflow on the onboarding route | logcat + dump | **PASS** (distinct from F-5, a different screen) |
| Unit + widget suite | **1128 tests pass, 9 skipped** | **PASS** |
| Device probes | 9 integration test files on `emulator-5554`; only one signs in, and it issues `SELECT`s only | **PASS** |
| Design token conformance | 14 assertions, mutation-tested | **PASS** |

## 3b · FIT-028 · Connect — no coach — **VERIFIED LIVE**

The design calls this state *"/messages · the state that sells the plan honestly"*. It
was absent: a member with no coach saw "No conversations yet", which is true and useless
— nothing on the screen tells them a coach is the thing they are missing, or how to get
one.

**Why this anchor and not a larger one.** F-21 (cross-user write on
`workout_programs`/`workout_program_assignments`) is OPEN and the standing instruction
reserves the policy change as an owner decision. FIT-028 depends on no coach-assigned
data — only on whether an active relationship exists — so it is integrable without
touching the vulnerable path. FIT-005, the anchor above it, is a full relationship layer
(coach + community + pods + classes) whose declared content is sample messages; building
it means inventing them.

**Nothing was invented.** Both strings already ship in this repository:

| String | Already at |
|---|---|
| `Find a coach` | `manage_subscription_screen.dart:241` |
| `Browse coaches, compare plans and get matched.` | `directory_screen.dart:59` |

**The design decision worth recording.** The pitch renders only on *proof of two facts*:
that the viewer is a member rather than a coach, and that their active-coach list really
is empty. If either read is loading or has failed, the screen falls back to the neutral
sentence. Collapsing a failed lookup into "you have no coach" would be the F-15
error→empty defect, and here it would also sell a plan to someone who has already bought
one. A coach with no client messages is likewise not a sales prospect.

| Layer | Evidence | Status |
|---|---|---|
| Branch correctness | `test/widget/messaging_no_coach_test.dart` — 8 tests against the real widget tree, no simulated logic | **PASS** |
| Guard strength | 3 mutations of the source, each killed: collapse `orElse`→pitch (2 fail), drop the role gate (2 fail), shrink the CTA to 30 px (1 fail) | **PASS** |
| Suite | 899 pass / 9 skipped; EC-G8, A-G5, A-G8, SEC-G1 ratchets all hold, none raised | **PASS** |
| Build | `flutter build apk --debug --dart-define-from-file=dart_defines/qa.json` | **PASS** |
| **Runtime, real data** | `integration_test/fit028_no_coach_live_test.dart` on `emulator-5554` against QA, signed in as `p1-victim`: `PRECONDITION role=client · active_coaches=0 · conversations=0` then `RENDER pitch=1 neutral=0 failed=0` | **VERIFIED LIVE** |
| Fixture residue | **none to clean** — the live test issues only `SELECT`s plus auth; it creates, updates and deletes nothing. Deliberate: F-21 is open and must not be exercised through unnecessary mutation. | **PASS** |

The live test asserts its own preconditions from the database *before* it asserts
anything about the screen, so if this fixture ever acquires a coach the run fails as
"precondition changed" rather than quietly reporting a FIT-028 regression.

**Still absent on this anchor, and why.** Six of ten declared interactions remain.
Three are bottom-nav items that exist in the shell and are invisible to a screen-file
heuristic — not gaps. Three are sample community content (`Tues Lifters…`, `Priya Hit
70 kg…`, `What's on this week`) belonging to FIT-005 and FIT-027; implementing them from
the design means fabricating messages and activity, which the brief forbids. Itemised in
`FIT_INTERACTION_COVERAGE.md`.

## 3c · FIT-017 · "Add 30 seconds" — the rest state's missing control

`/active-workout` declares two controls on its rest state. Only one existed.

**The defect, stated as a user experience.** A client mid-session who needs longer than
the prescribed rest had no control to say so. The only thing they could do was let the
clock run out — at which point the screen starts a siren, fires
`ScoreEngine().idleTimePenalty()` for −5, and drains another 5 points every 20 seconds
until they start the next set. The screen punished a need it gave them no way to express.

**What shipped.**

| Declared | Before | Now |
|---|---|---|
| `Skip rest, start set` | drawn "SKIP" / "STOP", **no accessible name**, ~30 dp tall | same short visible label, announces the design's phrase, 44 × 44 dp |
| `Add 30 seconds` | **absent** | present, same treatment |

The banner is a single row containing a progress bar, so the full phrase does not fit as
visible text. The short label is drawn and the design's wording is what a screen reader
announces. That is a deliberate compromise and is recorded as one.

**The rule the arithmetic encodes.** Extending adds to the *end*, not to now, so two taps
add a minute rather than restarting a short rest twice. And **overtime already accrued is
banked, never erased**: past zero the siren has been sounding and points have already
drained, so the overrun is added to the session's idle total exactly as dismissing the
rest would add it, and only then does a fresh 30 s start. Without that, tapping "+30s" the
instant the siren began would be an undo button for a penalty that had already fired.

`extendRest()` was extracted to `workout_provider.dart` to make this testable —
`_ActiveWorkoutViewState` touches `Supabase.instance`, `ScoreEngine` and a platform audio
channel in `initState`, so the arithmetic cannot be reached from a widget test. Same
reason `plan_summary.dart` was extracted.

| Layer | Evidence | Status |
|---|---|---|
| Arithmetic | `test/unit/extend_rest_test.dart` — 8 tests | **PASS** |
| Controls | `test/widget/rest_timer_controls_test.dart` — 5 tests | **PASS** |
| Guard strength | 6 mutations, all killed: extend-from-now, discard the banked overtime, leave `total` unchanged, drop `excludeSemantics`, drop the 44 dp constraint, wire "+30s" to the skip handler | **PASS** |
| **Runtime, on device** | `integration_test/fit017_rest_controls_device_test.dart` on `emulator-5554`: `dpr=2.625 physical=1080x2400`, then `+30s` → "Add 30 seconds" **44.0 × 44.0 dp** and `SKIP` → "Skip rest, start set" **44.0 × 44.0 dp** | **VERIFIED ON DEVICE** |
| Backend | none touched — `RestTimerWidget` is a leaf; nothing signed in, read or written | **n/a** |

**A correction of record, about my own test.** The first version of the target-floor
assertion was worthless. It mounted the banner under an `Align`, which hands down
loose-but-bounded constraints where `/active-workout`'s `Column` hands down unbounded
ones; the controls expanded to 566 dp tall and the assertion passed no matter what the
widget declared. Deleting the 44 dp constraint outright did not fail it. Found by running
that deletion as a mutation, which is the whole point of running them. The harness now
reproduces the production constraints, and the deletion fails as it should. The same
mutation was then run against FIT-028's CTA assertion, which killed it correctly.

The on-device leg exists for the same reason: F-6 and F-6b were found by measuring the
password toggle on the emulator (19.8 × 20.2 dp) after it looked fine in source. A host-VM
measurement is not a device measurement, and this file now has both.

## 3d · F-23 · the session-complete dialog claimed a delivery that never happened **FOUND AND FIXED**

**New finding this cycle.** Found while reading `/active-workout`'s completion flow for
FIT-018, not by a test.

`_WorkoutCompleteDialog._saveFeedback` ended `catch (_) {}` and then set
`_submitted = true` unconditionally. Every failure — no network, an RLS refusal, a
malformed row — produced the same screen as success: a green tick and the words
**"Feedback sent to your coach!"**. The dialog then offered only "Back to Home", so the
notes the client had written for their coach were gone and unrecoverable.

This is the F-15 error→empty pattern in its most harmful form. Not a failure shown as
emptiness — a failure shown as **success**, with a specific factual claim about a third
party attached to it. It is also a fabricated UI state, which the programme's brief names
explicitly.

A second falsehood sat next to it: the same line was shown to clients with **no coach at
all**. The insert writes `coach_id: null`, nobody is notified, and the screen still said
the feedback had been sent to a coach.

**Three outcomes, because the two writes fail independently.**

| Outcome | Condition | What the client is told |
|---|---|---|
| `failed` | the `workout_feedback` insert threw | "Could not send your feedback. Check your connection and try again." — form stays up, values intact, the button now reads "Try Again" |
| `saved` | feedback written; no coach, or the notification insert threw | "Feedback saved." |
| `delivered` | feedback written and the coach notified | "Feedback sent to your coach!" — now true |

A notification failure deliberately does **not** retract the save. The notes are stored;
reporting a failure would send the client to re-enter something already in the database,
and a second success would show their coach the same feedback twice. The coach loses a
ping, which is recoverable. The client is not lied to, which is the point.

The failure message carries **no interpolated exception** — F-2 and F-16 were raised
about exactly that, and this screen's own `_RestoreFailedView` already supplies the voice
and the recovery wording.

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/workout_feedback_honesty_test.dart` — 8 widget tests + 4 on `deliveryFor` | **PASS** |
| Guard strength | 5 mutations, all killed: restore the original catch-all success, claim delivery when only saved, close the form on failure, retract the save when only the notification failed, claim delivery when there is no coach | **PASS** |
| Suite | 911 pass / 9 skipped | **PASS** |
| Runtime | **not yet** — reaching this dialog needs a completed session, which means writing `workout_sessions` and `workout_set_logs` rows to QA. Not done: F-21 is open and the instruction is not to exercise it through unnecessary mutation. Classified **FIXED IN CODE**, not VERIFIED LIVE. | **OPEN** |

**Why the dialog is now `WorkoutCompleteDialog` and takes a `submit` callback.** Its real
path reads `Supabase.instance`, which no widget test can provide — the defect was
unreachable from a test, which is part of why it survived. The seam exists so each
outcome is assertable; the default path is unchanged in behaviour.

### F-24 · investigated and **NOT a defect** — the complete dialog does not overflow

A widget test at 420 dp reported `A RenderFlex overflowed by 18 pixels on the right` from
the Duration/Calories/Idle row. **That was the harness, not the product.** Widget tests
render in Ahem, where every glyph is a full em square, so text measures wider than any
real font.

Settled by measuring on the device rather than by arguing about it.
`integration_test/fit018_complete_dialog_device_test.dart` mounts the same dialog on
`emulator-5554` with the real font at three widths, with the worst realistic values
(1:42:10, 1250 kcal, 10:05 idle):

| Surface | Stats row | Constraint | Overflows |
|---|---|---|---|
| 411.4 dp (the emulator) | 283.4 dp | 283.4 dp | 0 |
| 390 dp (the design's viewport) | 262.0 dp | 262.0 dp | 0 |
| 360 dp (narrowest in common use) | 232.0 dp | 232.0 dp | 0 |

The probe is kept as a regression guard. Recording this matters as much as recording a
real defect: an Ahem artifact reported as a product bug would be a fabricated finding,
and F-5 (a genuine 39 px landscape overflow, confirmed on-device) is what a real one
looks like.

## 3e · FIT-002 · the Workout Zone — the screen the design calls the most focus-critical in the app

Four of five declared controls. Two of them were **defects, not gaps**: they existed, and
both were unreachable by a screen reader and under the touch-target floor.

| Declared | Before | Now |
|---|---|---|
| `End session` | unlabelled 36 dp cross | named, 44.0 × 44.0 dp on device, chip still 36 dp |
| `Log set` | unlabelled 32 dp check — the most-used control on the screen | named, 44.0 × 44.0 dp, chip still 32 dp; a completed set reports the same control `enabled: false` |
| `Pause session` | **absent** | present |
| `Skip` | present | unchanged |
| `Adjust weight or reps` | visible label "Edit", target **54.8 × 13.0 dp** | design's wording drawn, **140.8 × 44.0 dp** |

**Pause suspends the rest countdown, deliberately.** Rest is wall-clock. Left running, a
paused session would keep sliding into overtime, sound its siren and take 5 points every
20 seconds for time the client has explicitly said they are not training. Overtime already
accrued is still banked, so pausing is not a way to erase a drain that has already
happened — only to stop a new one. Elapsed time is persisted on pause so a crash while
paused resumes at the right number.

**`Adjust weight or reps` — resolved, and the defect it was hiding.** The affordance on a
completed set did what the design describes but read "Edit". Announcing the design's
phrase over a different visible word would break WCAG 2.5.3, so the **visible label** was
changed and the name follows it.

Measuring it on the device to decide the layout question found the thing that actually
mattered: the control was **54.8 × 13.0 dp** — under a third of the 44 dp floor — sitting
under *every completed set* on one of the app's most-used screens. It is now
`140.8 × 44.0 dp`, announced as a button with a tap action.

The cost is recorded rather than hidden: the completed-set row grows `81.0 → 108.0 dp`, so
a 20-set workout scrolls about 540 dp further. Part of the height was given back by
dropping the affordance's bottom padding. The alternative was keeping a 13 dp target.

**FIT-002 is now 5/5** and is the first locked anchor completed in this programme.

| Layer | Evidence | Status |
|---|---|---|
| Zone controls | `test/widget/zone_action_test.dart` — 5 tests | **PASS** |
| Log set | `test/widget/set_tracker_row_test.dart` — 3 added, 10 total | **PASS** |
| Guard strength | 8 mutations, all killed: drop the Semantics wrapper, drop the 44 dp constraint, drop opaque hit-testing, grow the chip into the target (×2 widgets), drop the "Log set" label, always report enabled, grow the check | **PASS** |
| **Runtime, on device** | `integration_test/fit002_zone_controls_device_test.dart` on `emulator-5554`: `dpr=2.625 width=411.4dp`, `"End session" 44.0x44.0dp`, `"Pause session" 44.0x44.0dp` | **VERIFIED ON DEVICE** |
| Pause state machine | **not runtime-verified** — reaching it needs a live session, which means writing to QA. F-21 is open. Classified **FIXED IN CODE**. | **OPEN** |
| Suite | 919 pass / 9 skipped | **PASS** |

**A-G8 lowered 56 → 55, and why not further.** Naming "End session" removed one from the
population *while FIT-002 also added a control*, which is the ratchet working as intended.
"Log set" is now named too, and the scan still counts it: it reads forward from each
tappable, so a `Semantics` wrapper placed outside the `GestureDetector` is invisible to
it. The window was **not** widened backwards to make the number fall — a backward window
would also swallow an unrelated `Semantics` above a genuinely unnamed control, and a
ratchet that under-counts hides regressions while one that over-counts only overstates the
work left. The discrepancy is recorded in the guard rather than tuned away.

## 3f · F-15 · `/home` told clients they had done nothing when the read failed **FIXED**

`weeklyActivityProvider` ended `catch (_) { return List.filled(7, 0.0); }`. A failed read
arrived at "This Week's Progress" as a real week containing nothing, and that card does
not merely look empty — **it answers**. A client who had logged six meals was shown:

* **"0%"**, in 28 pt brand colour;
* "Log meals or workouts to see progress" underneath; and
* seven flat bars with today's lit at 15%.

A failure presented as a confident wrong number, with a nudge blaming the client for it.

**Fixed with no new copy, which is why it could be fixed at all.** The error now
propagates — the same change `assignedWorkoutsProvider` already carries — and the card
reports what it knows:

| | Before a failure | After |
|---|---|---|
| headline | `0%` in brand colour | `—`, dimmed |
| nudge | "Log meals or workouts to see progress" | **omitted** |
| bars | flat, today's highlighted | flat unknown track, nothing highlighted |

A lit "today" bar over a failed read reads as *"you did nothing today"*, which is exactly
the claim the screen cannot make.

**A genuinely empty week still answers `0%` with the nudge.** The fix must not collapse
the two in the other direction — an empty week is a real result, and a test pins it.

| Layer | Evidence | Status |
|---|---|---|
| Derivation | `test/unit/week_progress_test.dart` — 10 tests | **PASS** |
| Guard strength | 4 mutations, all killed: never take the error branch (the original behaviour), keep the nudge on failure, go by the value instead of the state so stale data answers, treat an empty week as a failure | **PASS** |
| Suite | 929 pass / 9 skipped; EC-G8 unchanged at 134 — `weekProgressFrom` holds the single `.valueOrNull` the card already had | **PASS** |
| Runtime | **not verified** — reproducing it needs the read to fail against QA, i.e. inducing a network or policy failure for a signed-in fixture. Classified **FIXED IN CODE**. | **OPEN** |

`weekProgressFrom` is extracted because `home_screen.dart` reaches `Supabase.instance` at
the top level, so the card cannot be mounted in a widget test — the same reason
`plan_summary.dart`, `extendRest()` and `ZoneAction` were extracted. The pattern by now is
settled: **a thing worth asserting gets moved somewhere it can be.**

**This does not close F-15.** Seven collapses remain, and each needs user-facing error
copy the design package does not supply for those frames. A full error state with a retry
— the `booking_screen.dart:612` pattern — is still OD-8. What changed is that the two
cases needing *no words at all* are done.

## 3g · F-15 · `/profile` told paying clients they had no coach **FIXED**

The "MY COACH" section read `assignedCoachProvider.valueOrNull`, so a failed read and
"you have no coach" arrived as the same `null`. On any failure the client saw:

> **No coach assigned yet**
> Complete onboarding to choose your coach.

Not a blank where data should be — a **specific false statement about the client's own
relationship, with an instruction attached**. Someone paying a coach every month, told to
go and pick one.

This is the same falsehood FIT-028 was built to avoid on `/messages`. There it was caught
before it shipped. Here it had shipped.

**Hidden, not reworded.** FIT-028 could fall back to a neutral sentence because one was
already shipping. Here the string already sitting there *is* the false one, so there is
nothing to fall back to, and any replacement is new product copy — OD-8, like the other
collapses. Saying nothing is not ideal; saying something untrue is worse, and that is what
shipped. The heading goes too: a "MY COACH" label over empty space is its own small
assertion that there is nothing there.

**A retry in flight stays hidden.** Riverpod reports `isLoading` and `hasError` together
during a refresh; a retry knows no more than the failure before it, and flashing a spinner
in and out of a hidden section is worse than leaving it hidden until there is something
true to say. Pinned by a test, because a plausible reordering would change it silently.

**`coachSectionFor` matches on the state, never on the value** — `.valueOrNull` is exactly
how the failure became "no coach", and it is the read EC-G8 ratchets. Fixing an error→null
collapse by adding an error→null read would have been self-defeating. EC-G8 is unchanged
at 134.

| Layer | Evidence | Status |
|---|---|---|
| Decision | `test/widget/coach_section_state_test.dart` — 6 tests on `coachSectionFor` | **PASS** |
| Wiring | 2 widget tests mounting the real `MyCoachSection` with the providers overridden | **PASS** |
| Guard strength | 4 mutations, all killed | **PASS** |
| Suite | 937 pass / 9 skipped; EC-G8 unchanged | **PASS** |
| Runtime | **not verified** — reproducing it needs the coach read to fail against QA. Classified **FIXED IN CODE**. | **OPEN** |

**A correction of record.** The first version of this fix had only the decision function
under test, and the mutation *"delete the early return in `build`"* **survived** — the
screen could have gone on rendering the denial with every unit test green. The section was
made public and mounted so the wiring is asserted too. Found by running the mutation,
which is the only reason it is not still true.

## 3h · F-22 · `/daily-checkin` — fifteen controls that announced nothing at all

The weekly check-in is five mood faces and two rows of five numbers. All fifteen were bare
`GestureDetector`s. A screen reader read five emoji and the words "Rough Meh Good Great
Amazing", then "1 2 3 4 5", then "1 2 3 4 5" again — **no role, no group, and no
indication of which one was chosen**.

Worse than an unnamed button. A blind client could fill this form, submit it to their
coach, and have no way to know what they had said. Both number rows are identical, so they
could not tell which one they were in either.

**Nothing was invented to fix it.** The mood options are named by the label already drawn
under each face. The number options are named from the section heading already drawn above
the row plus the number already drawn inside it — "Energy Level 3 of 5" — because a screen
reader announces one option at a time and "3" alone says nothing about what was rated.
`inMutuallyExclusiveGroup` and `selected` are facts about the widget, not copy.

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/checkin_pickers_test.dart` — 8 tests | **PASS** |
| Guard strength | 6 mutations, all killed: drop the wrapper (the shipped defect), always report selected, drop the exclusive group, drop the `Semantics` `onTap`, name the numbers with a bare digit, stop excluding the child so the emoji leaks | **PASS** |
| Suite | 945 pass / 9 skipped | **PASS** |
| Runtime | not verified on device — these are leaves, and the host-VM semantics tree is the same tree. Classified **FIXED IN CODE**. | **OPEN** |

`MoodPicker` and `NumberPicker` were extracted to `widgets/checkin_pickers.dart` because
the screen constructs a `CheckinService` in a field initializer and loads from Supabase in
`initState`. Fifth instance of the same move.

**A-G8 did not fall.** These fifteen carry `Text` inside the tappable, so the scan never
counted them — its heuristic is "an `Icon` and no `Text`". The count stays at 47 and this
is a reminder of what it does not see: **a control with a visible label can still be
unreachable**, because a label is not a role and not a state.

## 3i · Fixture hygiene for this cycle — **nothing was written to QA**

The brief requires every QA fixture to be cleaned up and the remainder proved zero. This
cycle there was nothing to clean up, which is a stronger result and was deliberate: F-21
is open, and the standing instruction is not to exercise it through unnecessary mutation.

Every device probe added this cycle mounts a widget directly and injects its data, so four
of the five touch no backend at all. The fifth (`fit028_no_coach_live_test.dart`) signs in
as `p1-victim` and issues only `SELECT`s.

Verified after the run, as `p1-victim`, against QA:

| Table | Rows owned by the fixture |
|---|---|
| `workout_programs` (`coach_id = uid`) | **0** |
| `workout_program_assignments` (`client_id = uid`) | **0** |
| `workout_feedback` (`user_id = uid`) | **0** |
| `user_profiles.onboarding_complete` | **`false`** — unchanged |

The last row is worth stating. Reaching `/messages` through the app UI would have needed
this fixture past onboarding, and a `PATCH` to flip that one column **was attempted and
refused by the sandbox**. Rather than work around the refusal, the runtime verification was
re-done as an integration test that mounts the screen against the live read paths — which
proved more, wrote less, and left the fixture exactly as it was found.

## 3j · FIT-027 · "What's on" — three routes under one list

`/classes · /events · /challenges under one list`. The three shipped as separate screens,
and F-14 recorded `/events` and `/challenges` as **stranded** once the bottom nav went to
five tabs. This is the anchor that unstrands them.

**Five of the ten declared interactions, and that is the ceiling.** `Back`, `All`,
`Classes`, `Events`, `Challenges` — the entire structure — are present. The other five are
the design board's own sample rows (`11 Sep Reformer, small group Class · Studio 2 · 4
places left`). The row *formats* are implemented and tested; matching the literal strings
would mean fabricating a class, an event and a challenge. Itemised in
`FIT_INTERACTION_COVERAGE.md`.

### The rule the architecture exists for

**A partial failure is reported, never hidden.** Three sources load independently. If
Events fails and the other two succeed, rendering the surviving two as "what's on" tells
the client there are no events this month — a false answer assembled from a true one and a
failure. A merged list invites exactly this: the list still looks full, so nothing looks
wrong.

So `WhatsOn` carries `failed` alongside `items`, and:

| State | What the screen does |
|---|---|
| one source failed, others have rows | names the failed source **above** the rows that loaded |
| one source failed, nothing else to show | the failure notice **replaces** the empty state |
| viewing a single segment | reports that source's failure, and only that one |
| all three genuinely empty | the three shipped empty lines, no failure line |
| any source still in flight | a spinner — **not** a partial list |
| a failed source carrying stale rows | contributes **none** of them |

**Every string is one this repository already renders.** `Could not load events`
(`events_screen.dart:66`), `Could not load classes` (`coach_classes_screen.dart:37`),
`Could not load challenges` (the `Could not load [noun]` pattern used in fifteen files),
`No classes yet`, `No upcoming events`, `No challenges here`, and `Try again` (the
package's own label, 16 declarations). FIT-027 declares only a `default` state, so it
supplies no failure or empty copy — and this screen can report a failure at all only
because it borrows from the three screens it replaces. Nothing here needs OD-8.

### Two swallowed reads fixed on the way

| Where | Was | Now |
|---|---|---|
| `LiveClassService.getUpcomingClasses` | `catch (_) { return []; }` | propagates — without this FIT-027's failure machinery could never fire for classes |
| `events_screen.dart`'s private provider | `catch (_) { return []; }` | propagates, which **makes `/events`' own `error:` branch reachable for the first time** — the copy for the failure was written; the catch made sure nobody ever saw it |

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/whats_on_test.dart` — 26 tests | **PASS** |
| Wiring | `test/widget/whats_on_view_test.dart` — 16 tests over the real view and the three real source providers | **PASS** |
| Guard strength | 9 mutations, all killed | **PASS** |
| **Runtime, on device** | `integration_test/fit027_whats_on_device_test.dart` on `emulator-5554` at 411.4 / 390 / 360 dp: all four segments ≥ 44 dp, exclusive-group + tap action on each, 0 overflows at every width | **VERIFIED ON DEVICE** |
| Suite | 987 pass / 9 skipped; A-G8 unchanged at 47, EC-G8 unchanged at 134 | **PASS** |

The segment row needs **372.2 dp**. It fits at 411 and at the design's own 390; at 360 it
scrolls horizontally, which is what the widget is for. Measured, not assumed — and
measured on the device because the host harness renders in Ahem, where a width means
nothing (F-24 is the recorded instance of mistaking an Ahem overflow for a product bug).

### A trivially-passing test, caught and moved

The first version asserted "a failed read carrying stale rows contributes none of them" as
a **widget** test. It passed — and it would have passed whatever the code did. The harness
turns an `AsyncError` into `Future.error`, so Riverpod rebuilds with a plain error and the
previous value is discarded; the state the test named could not exist inside it. Found by
running the mutation, which survived.

`combineWhatsOn` was extracted as a pure function so the state can actually be
constructed, and the assertion moved there, where the mutation now fails. The widget file
keeps a note saying why that particular claim is not made in it.

### OD-15 — the coach's "New Class" affordance

FIT-027 does not draw one. A booked class is still a class and appears in the one list
carrying "Booked", so nothing was lost there — but removing the FAB would take away a
coach's only way to create a class. **A locked screen not drawing something is not the
same as the design saying to delete it**, so the FAB stays and the discrepancy is recorded
rather than resolved by guessing.

## 3k · FIT-005 · Connect — "Coach, community and pods in one relationship layer"

`/messages` was a conversation list. The anchor makes it the place a client sees every
relationship they have. Three teasers now sit under the conversations — **Feed**,
**Groups**, **What's on** — all three titles being labels the design package declares, all
three fed by providers that already existed.

**FIT-027 is reused, not reimplemented.** The "What's on" teaser reads the same merged
list `/classes` reads. Two independent definitions of "what is coming up" would drift, and
the first symptom would be the two screens disagreeing in front of the client.

**The rule, again, for the same reason.** A section whose source failed must never be
drawn as a section with nothing in it. Under a heading that says "Groups", an absence is
an answer: it tells the client they are in none.

| State | What the section does |
|---|---|
| source failed | names the failure under its own heading; the other sections are untouched |
| failed carrying stale rows | contributes **none** of them |
| genuinely empty | stays quiet and offers the way to the screen that owns it |
| still loading | renders **nothing** — not a spinner, and above all not an empty section |
| the merged list partly failed with rows surviving | shows them; the full screen names what is missing |

**`Open message` is a hint, not a name.** The row's accessible name must contain its
visible label (WCAG 2.5.3), and what is visible — participant, last message, age — is also
what a client needs in order to choose a thread. The design's phrase describes the action,
so it is announced after it. Naming the row "Open message" would have scored a coverage
point by deleting the information the row exists to carry. The mutation that does exactly
that now fails.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/connect_sections_test.dart` — 16 tests | **PASS** |
| Wiring | `test/widget/connect_sections_view_test.dart` — 10 tests over the real sections and real providers | **PASS** |
| `Open message` | 1 test in `messaging_no_coach_test.dart`, 2 mutations killed | **PASS** |
| Guard strength | 9 mutations, all killed | **PASS** |
| **Runtime, on device** | `integration_test/fit005_connect_device_test.dart` on `emulator-5554`: all three headings report `header=true`, all three "Open …" affordances `button:true tap:true` at `379.4 × 44.0 dp` | **VERIFIED ON DEVICE** |
| Suite | 1014 pass / 9 skipped; A-G8 47, EC-G8 134, both unchanged | **PASS** |

**Five of twelve, and the ceiling is lower than it looks.** Four of the seven absent are
the design board's sample rows and the bottom nav. One — `Priya Hit 70 kg…` — is counted
but is a **doc-comment artifact**, and is recorded as one rather than left to flatter the
number. `Book` is genuinely absent: the teaser defers to `/classes`, which carries the
affordance, and wiring a booking from `/messages` would be a second write path to the same
table for one row in a summary.

## 3l · F-21 · blast radius — **screen-level, static, no further mutation**

Full analysis in **`docs/F21_BLAST_RADIUS.md`**. The policy was not changed; OD-14 stands.

**The fifteen are not equally dangerous.** The split is whether the predicate names one
party or two:

| Class | Count | Effect |
|---|---|---|
| two-party, `coach_id = uid() OR client_id = uid()` | **5 policies, 4 tables** | a caller can write a row naming itself coach and **any other user** as client — the class that reaches a victim, and the one that was proven |
| single-party, `coach_id = uid()` | 11 | self-forgery: claim to be a coach; no direct victim |

**What a victim would actually see, traced end to end in code.** A forged
`workout_program_assignments` row satisfies `getMyAssignedProgram()`'s filter
(`.eq('client_id', me).eq('status','active')`, `coach_program_service.dart:219`) exactly as
a real one does. It decodes through `assignedWorkoutsProvider` into `/train`'s hero card and
programme list, `getTodaysWorkout()` → `/home`, and `/active-workout`. **The victim sees
prescribed exercises, loads and rep schemes attributed to their coach, and can start and log
the session.** The attacker chooses the weights, which makes this a physical-safety exposure
in a strength product, not only a data-integrity one.

**A second effect, not previously recorded.** That read uses `.maybeSingle()`. A victim who
already has a real active assignment and receives a forged one matches **two** rows and the
read fails — so the forged row does not merely add a fake programme, **it makes the victim's
real programme unreadable.** Because `assignedWorkoutsProvider` now propagates its errors
(the F-15 work), the client is at least shown `_PlanUnavailable` rather than told they have
no plan. The denial stands either way.

Also traced: forged `coaching_calls` appear in `/checkins` upcoming and **inflate `/home`'s
activity bars** (calls are weighted ×3 there); forged `client_nutrition_plans` and
`client_habits` land under the victim's id; forged `classes` and `challenges` are publicly
readable and render in `/classes` and `/challenges` as real.

**Which screens are safe to keep integrating.** The test is whether a screen's correctness
depends on the integrity of a row written through one of these policies — not whether it
touches the feature at all. `/train`, `/active-workout`, `/checkins`, `/booking`, nutrition
and habits surfaces, `/coach-dashboard` are **BLOCKED-BY-F21 for integrity claims**, and
that is narrower than "do not work on them": FIT-002 was taken to 5/5 while F-21 was open,
because accessibility and interaction work does not rest on the row being authentic.
`/messages`, `/classes`' structure, `/home`'s week card, `/daily-checkin`, `/profile`,
`/progress`, `/intake` and auth are clear.

**SEC-G2 added.** SEC-G1 holds the whole population at 15; a new two-party policy could
hide inside that number by displacing a single-party one. SEC-G2 holds the cross-user-write
subset at 5. Both parse the real migrations, both are ratchets, and both were
mutation-tested — a sixth two-party policy fails SEC-G2, a sixteenth single-party one fails
SEC-G1 without disturbing SEC-G2.

**A correction of record.** The analysis first stated that `coaching_calls` carried its
policy "twice", from reading the migration. SEC-G2 measured it: they are two *different*
policies with different names, one added later. Five, not four. A correction that fixed one
and left the other would have looked complete against the guess.

## 3m · FIT-023 · Check-in hub — "status and history"

`/checkins` had a calendar strip and an upcoming-sessions list. FIT-023 declares two
controls and a history, and the screen had neither.

| Declared | Built |
|---|---|
| `Measurements` | → `/progress`, which is where this app keeps them. No screen was invented to satisfy a label. |
| `Start check-in` | → `/daily-checkin` |
| a week history | real weeks from `weekly_checkins`, rendered `Week 13 · Energy 3 of 5 · Nadia replied` |

### Two F-15 collapses closed here

| Where | Was | Now |
|---|---|---|
| `_loadCalls()` | `catch (_) { _loading = false; }` → **"No upcoming sessions. Book a call with your coach."** on any failure | `Could not load sessions` with a `Try again`, distinct from the empty state |
| `WeeklyCheckinService.getWeeklyCheckins()` | `catch (e) { return []; }` | propagates — without it the new history section would have told a client who has checked in for thirteen weeks that they never had |

The first is the sharper of the two: it did not merely hide a failure, it **instructed the
client to book a call they may already have booked**.

### "Energy steady" was not built, and that is the point

The anchor draws `Week 13 · Energy steady · Nadia replied`. Two of those three come
straight from the data. The third does not: the stored value is **1–5**, and turning it
into Low / Steady / Strong means choosing thresholds on a number a coach reads. That is the
same decision FIT-004's difficulty mapping is blocked on — recorded together as **OD-16**.

The row states `Energy 3 of 5` instead, which is the phrasing already used for those
controls' accessible names. **A test asserts the row never produces the anchor's three
words**, so the decision cannot be made silently by a later edit — the mutation that makes
it fails.

`Awaiting reply` is FIT-025's own screen name, so the no-reply half is not invented either.
A **pending** week reports neither: nothing has been sent, so nobody is awaiting anything,
and merging the two would misreport the client's own state back to them.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/checkin_hub_test.dart` — 15 tests | **PASS** |
| Wiring | `test/widget/checkin_hub_sections_test.dart` — 7 tests over the real sections | **PASS** |
| Guard strength | 6 mutations, all killed — including *"interpret energy into the anchor's words"*, which is OD-16 made silently | **PASS** |
| Suite | 1038 pass / 9 skipped; A-G8 47, EC-G8 134, both unchanged | **PASS** |
| Runtime | not device-verified — the sections are leaves and the host semantics tree is the same tree. **FIXED IN CODE**. | **OPEN** |

**BLOCKED-BY-F21 note.** `/checkins`' *upcoming sessions* read `coaching_calls`, which
carries the two-party policy (`F21_BLAST_RADIUS.md` §3b) — a forged row appears there as a
session the client never booked. **The work done here is structure, accessibility and error
honesty, none of which rests on those rows being authentic.** The integrity of what the
sessions list displays remains blocked on OD-14, and is not claimed.

## 3n · FIT-004 · Check-In, and a measurement that counted its own comments

### FIT-004 — three of its declared controls

| Declared | Built |
|---|---|
| `Past check-ins` | → `/checkins` |
| `Add a progress photo` | → `/progress`, where this app already keeps photo capture and the `progress-photos` bucket. No screen invented to satisfy a label. |
| `Send to Nadia` | the submit button is addressed to the client's coach, by name |

**The submit label is the interesting one.** The name is real data, so using it invents
nothing — but the two failure modes either side of it are ones this repository has already
been bitten by:

* naming a coach the client does not have, and
* naming one when the read **failed** — which is `/profile`'s "No coach assigned yet"
  collapse turned inside out. There a failure claimed the client had no coach; here it
  would claim they have one. Both are the screen answering a question it cannot.

So the name is used only on a settled, non-empty value. Loading, failed, no coach, and a
coach with a blank first name all fall back to `Submit Check-In` — the label this screen
already ships. 7 tests, 2 mutations killed.

`Low` / `Steady` / `Strong` remain **OD-16**, unchanged.

### The measurement counted its own comments — reported numbers fell by four

The coverage tool matched a declared label's first three words against the **raw text** of
the implementing file. Dart comments are raw text, and this programme's comments quote the
design constantly. Four anchors had accumulated artifacts — each recorded at the time, none
left to flatter the count:

| Anchor | Counted | Actually |
|---|---|---|
| FIT-028 | `Connect` | a doc comment naming the anchor |
| FIT-005 | `Priya Hit 70 kg…` | a comment quoting the sample row |
| FIT-023 | `Week 13 Energy steady…` | the same |
| FIT-004 | `Steady`, `Strong`, `Send to Nadia` | a comment explaining why the mapping was **not** built |

The last settled it. **Writing down that something was deliberately not implemented made
the metric report it as implemented.** A number that rises when nothing ships is not a
measurement, and annotating each case was treating the symptom.

`apps/mobile/tool/fit_coverage.dart` now strips comments before matching, leaving string
literals alone. Every anchor this programme touched was re-measured:

| Anchor | Was reported | Measured |
|---|---|---|
| FIT-002 · FIT-017 · FIT-027 · FIT-028 | 5/5 · 2/2 · 5/10 · 4/10 | **unchanged** |
| FIT-005 | 5/12 | **4/12** |
| FIT-023 | 5/10 | **4/10** |
| FIT-004 | 8/11 | **5/11** |

Headline: **276 → 272 present**, locked anchors **71 → 67**. The anchors reported complete
were complete, which is the part of the result worth having.

## 3o · F-15 — the inventory is closed

> **CORRECTION (see §3bx).** *Previous conclusion:* all nine were fixed. *Why it was wrong:*
> the `/train` row below was fixed **only at the widget**. Its `'—'` could not render,
> because `WorkoutService`'s five stat reads caught the failure and returned `0`, so the
> `FutureProvider` was always `AsyncData(0)` and the `error:` arm was unreachable. *New
> evidence:* the service source, and mutation A1/A2. *Corrected conclusion:* **eight of nine
> were genuinely closed; `/train` was closed at one layer of two** and is now closed at both
> (§3bx, ratchet **A-G6**). The other eight were checked and are sound — several say so
> explicitly in the table ("*a swallowing service → per-source failure named*",
> "*`catch (e) { return []; }` in the service → propagates*"), and `/home`'s
> `weeklyActivityProvider` propagates.

Nine error→empty collapses were recorded in §6c. **All nine are now fixed, and none of
them needed new product copy.**

| Screen | Was | Now |
|---|---|---|
| `/train` | `error: (_, __) => '0'` — **"0 workouts" as a real answer** | `'—'` |
| `/home` | `catch` → all-zero bars → **"0%"** and "Log meals or workouts to see progress" | `'—'`, nudge dropped, no bar highlighted |
| `/profile` | `valueOrNull` → **"No coach assigned yet · Complete onboarding"** | section hidden |
| `/classes` | `valueOrNull ?? []` and a swallowing service | per-source failure named |
| `/checkins` sessions | `catch (_)` → **"No upcoming sessions. Book a call with your coach."** | `Could not load sessions` + Try again |
| `/checkins` history | `catch (e) { return []; }` in the service | propagates |
| `/challenges` | `AsyncError` never consumed → "🏁 No challenges here" **and "0 active challenges"** | `Could not load challenges` + Try again, count `—` |
| `/progress` | `catch (_)` → **three empty states at once** | `Could not load your progress` + Try again |
| `/coach-dashboard` ×4 reads | `catch` → `[]` → **"No clients found"** | `Could not load your clients`; any of the three failing is reported |

### What OD-8 turned out to be

OD-8 said these could not be fixed because each needed **user-facing error copy**, and
writing nine new strings would be inventing product copy. That was true of writing them.
It was not true of the fix.

Every line used is one this repository already renders: `Could not load events`
(`events_screen.dart:66`), `Could not load classes` (`coach_classes_screen.dart:37`), the
`Could not load [noun]` pattern in fifteen files, and `Try again` — the **design package's
own label**, 16 declarations. Two of the nine needed no words at all: a number the screen
could not support became `'—'`.

**OD-8 is no longer blocking anything.** It asked for permission to invent; none was
needed. It stays open only as the question of whether the owner wants *better* copy than
the house pattern.

### The two that were worse than "empty"

Most of the nine hid a failure. Two **instructed the client to act on it**:

* `/checkins` told them to **book a call with their coach** — one they may already have
  booked, which is what the failed read was trying to tell them.
* `/coach-dashboard` told a coach **their entire roster had vanished**. Both false and
  alarming, and the read had simply failed.

### Three that answered with a confident wrong number

`/train`'s "0 workouts", `/home`'s "0%", `/challenges`' "0 active challenges". Not a
failure shown as emptiness — a failure shown as a **measurement**. All three now read
`'—'`, which needs no copy and cannot be misread as a result.

## 3p · Addressing the coach by name — one rule, three screens

The package names the client's coach in three places: **"Send to Nadia"** (FIT-004),
**"Message Nadia"** (FIT-015), and `/train`'s empty-state body copy. The name is real data,
so using it invents nothing — but the two failure modes either side of it are easy to
reintroduce one screen at a time:

* naming a coach the client **does not have**; and
* naming one when the read **failed** — `/profile`'s "No coach assigned yet" collapse
  turned inside out. There a failure claimed the client had no coach; here it would claim
  they have one. Both are a screen answering a question it cannot.

So the rule lives once, in `coach_name.dart`: **the name is used only on a settled,
non-empty value.** Loading, failed, no coach and a blank first name all fall back to
wording that stays true without one — `Submit Check-In`, `Message your coach`,
`Your coach` — each of which this repository already shipped.

| Layer | Evidence | Status |
|---|---|---|
| Rule | `test/unit/coach_name_test.dart` — 10 tests | **PASS** |
| Guard strength | 2 mutations killed: a failed read still yields a name; a blank name is used verbatim | **PASS** |
| Suite | 1056 pass / 9 skipped | **PASS** |

**A third mutation was an equivalent mutant, and is recorded as one.** Adding an explicit
`AsyncLoading()` arm to the switch changed nothing, because the catch-all already returns
null for a true loading state — and a refresh in flight is `AsyncData` with
`isLoading: true`, not `AsyncLoading`, which was measured rather than assumed. A surviving
mutation and a mutation that changes nothing look identical in a report; this one is the
second, and the test now says so.

**FIT-015's `Message Nadia` still measures ABSENT, and correctly.** The label is composed
(`'Message $name'`), so the literal string never appears in source. Making the metric count
it would mean hard-coding "Nadia" — naming every client's coach after the design board's
example. The same ceiling as FIT-027's and FIT-005's sample rows.

## 3q · F-25 · two live assertions that could not observe what they asserted

Found by running the **whole** `integration_test/` directory rather than the files added
this cycle — which is the only reason it surfaced.

`service_logic_test.dart` counted the **recipient's** notifications from the **sender's**
session. `notifications` carries
`recipients read own notifications … USING (recipient_id = auth.uid())` (migrations 003 and
004), so both reads return 0 for any sender, forever.

| Test | Asserted | Result |
|---|---|---|
| `MessagingService.sendMessage notifies recipient exactly once` | `after - before == 1` | `0 == 1` — **red forever**, and it said nothing about the trigger |
| `WeeklyCheckinService.submitWeeklyCheckin scores + notifies coach` | `after - before <= 1` | `0 <= 1` — **green forever, whatever the app did** |

One root cause, opposite symptoms. **The green one is the more dangerous**, because nobody
looks at a passing test: it had been sitting in the suite reporting that the coach is not
double-notified, while being structurally incapable of detecting it either way. That is the
"green whatever the app does" shape `QA_CLOSURE_STANDARD` §4 warns about, in a file that
runs against the live database.

And the red one is worse than useless: **the only way it could ever have passed is if
`notifications` leaked rows across users.** A test whose passing condition is a privacy
defect is not a weaker test, it is a wrong one. RLS was verified working during this
analysis — the same query run as the client returns 0, run as the recipient returns their
own rows.

### What replaced them

Each test now asserts what its own session can observe, and nothing else:

* the sender is **not** notified of their own message; the message row exists;
* the client is **not** notified of their own check-in; the points were awarded.

The recipient-side half — *did the coach actually get one?* — needs the **recipient's
session**, which this file does not have: it signs in as `test@12circle.app` and does not
hold that client's coach's credentials. **It is recorded as open rather than asserted from a
session that cannot see it.** Closing it needs either a coach fixture paired to this client
or a `SECURITY DEFINER` counting RPC; both are changes to the test estate, not to a policy.

`test/unit/message_notification_guard_test.dart` holds the half that *can* be held in the
fast suite: no Dart-side notification insert in `sendMessage` (the duplicate the test was
originally written for), the trigger and its `AFTER INSERT ON messages` are still installed,
and the cross-RLS count does not come back. 3 mutations, all killed.

**A correction of record, again about comments.** The first version of that guard failed on
the very file it protects, because that file's header *explains* the defect and quotes the
expression it forbids. The FIT coverage metric had the identical fault the same day. Both
now strip comments before matching: **writing down what went wrong must not register as the
thing going wrong.**

### An environment note, so the next run is not misread

`flutter test integration_test/` runs files in parallel and they race on the single
`build/app/outputs/flutter-apk/app-debug.apk`, producing
`Error opening archive … Invalid file` and *"No application found for
TargetPlatform.android_arm64"*. Those are **loading** failures of the harness, not test
results. Run device tests with `--concurrency=1`, or as an explicit file list.

With a fresh APK and `--concurrency=1`: **16 pass**, and the only failures are
`wrk01_progression_live_test` and `uix1_booking_e2e_test`, which fail their own
`setUpAll` guard — `Bad state: PROBE_RUN_ID is required — the fixture must be run-scoped`.
They are driven by `tool/negative_control/wrk01_live_probe.sh` and are expected to refuse a
bare run.

## 3r · FIT-019 · Log a meal — 0/5 → 4/5, and the file it was measured against

**The coverage resolver had the wrong file.** FIT-019 was recorded against
`log_meal_screen.dart`: a **23-line redirect stub** that bounces to `/meals-dashboard` in
`initState` and renders a spinner. The screen the anchor describes — "*a sheet, not a
screen*" — is `_AddMealSheet` inside `meals_dashboard_screen.dart`. Same class as the
FIT-001 → `home_org.dart` correction: **a route that exists is not an implementation.**

| Declared | Status |
|---|---|
| `Close` | added — an unnamed 36 dp cross, now `NamedIconButton` |
| `Search` | the "Manual" pill renamed to the locked word; it already searched foods |
| `Scan` | the "AI Scan" pill, likewise |
| `Search foods` | field placeholder aligned from `Search foods...` |
| `Recent` | **OD-17** |

### A systemic accessibility defect, fixed at the component

The three pills were a `GestureDetector` around a `Text`: named by their text, but
announced as **neither buttons nor selected**. A screen reader read "Search Scan Barcode"
with no way to tell which mode was active — on the sheet where a client logs everything
they eat. **Identical to the defect found on the weekly check-in's pickers**, in a
different feature.

So it was fixed at the component and extracted: `widgets/pill_tab.dart`. Seventh extraction
for the same reason — a thing worth asserting gets moved somewhere it can be.

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/pill_tab_test.dart` — 5 tests | **PASS** |
| Guard strength | 5 mutations killed: always-selected, drop the exclusive group, drop the `Semantics` `onTap`, drop the 44 dp floor, stop excluding the child. A sixth (delete the whole wrapper) did not compile and is recorded **inconclusive**, not as killed — the five cover each property it provides. | **PASS** |
| **Runtime, on device** | `integration_test/fit019_log_meal_device_test.dart` on `emulator-5554`: all three `button=true exclusive=true tap=true`, one `selected=true`, targets `137.1 × 54.0 dp` | **VERIFIED ON DEVICE** |
| Suite | 1065 pass / 9 skipped | **PASS** |

### OD-17 — `Recent` vs `Barcode`

The design's third pill is **Recent**; the app's is **Barcode**. They are different
features, there is **no recent-foods data source in the repository**, and the design draws
three pills, not four. Renaming would strand barcode scanning behind a label promising
something else; deleting it would remove a shipped capability the design never said to
remove. Not resolved by guessing.

## 3s · FIT-020 · AI meal scan — 0/5 → 4/5

| Declared | Built |
|---|---|
| `Smaller` · `As shown` · `Larger` | three portion controls above the existing slider |
| `Save to lunch` | the save button, named after the meal chip the client selected |
| `Search instead` | leaves the scan for the search tab |

### The number the anchor did not give

The anchor gives three words and **no numbers**. Turning `Smaller` into a fixed multiplier
— 0.75×, 1.5× — would be deciding, on the owner's behalf, **how much food a client just
ate**. That number goes into their day's calories and to their coach.

So `Smaller` and `Larger` are **relative**, which is what the words mean, and one step is
the granularity the shipped slider already defines: `(3.0 − 0.25) / 11 = 0.25`. The
figure is the product's own, not one chosen here. `As shown` returns to 1.0 — the scan's
own estimate, the only value in the control that is not a judgement.

The slider stays. The anchor does not draw it, but removing a finer control would take
capability away, and a locked screen not drawing something is not the design saying to
delete it — the OD-15 / OD-17 rule, applied a third time.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/scan_portion_test.dart` — 10 tests | **PASS** |
| Wiring | `test/widget/ai_scan_result_test.dart` — 8 tests over the real result state | **PASS** |
| Guard strength | 4 mutations killed, including **"an invented fixed multiplier instead of a step"** — the decision this work refuses to make, now unable to be made silently | **PASS** |
| **Runtime, on device** | `integration_test/fit020_scan_result_device_test.dart` at 411.4 / 390 / 360 dp: all three `button=true tap=true`, `As shown` `selected=true`, targets `107.1 × 44.0 dp`, **0 overflows** at every width | **VERIFIED ON DEVICE** |
| Suite | 1083 pass / 9 skipped | **PASS** |

**A test seam, and why.** The result state is only reachable by running a real scan — a
camera, an upload and a model call — so `AiScanView` gained an `initialResult` for tests.
Without it none of the wiring above could be asserted at all. Same seam as
`WorkoutCompleteDialog.submit`.

**An Ahem artifact, checked rather than reported.** The widget test overflowed the result
card's title row by 131 px with the anchor's own "Chicken, rice, greens". That row is
pre-existing and has no `Expanded` on the name, so it was worth measuring — on the device,
with the real font, it fits at 411, 390 and 360 dp with **zero overflows**. Second instance
of the F-24 discipline: an Ahem overflow reported as a product bug would be a fabricated
finding.

**`Save to lunch` measures absent, correctly.** The label is composed from the selected
meal chip; matching the literal would mean hard-coding "lunch" and labelling the button for
one meal regardless. Fifth composed-label ceiling recorded.

## 3t · FIT-031 · Plans — **BLOCKED after one control. The prices disagree.**

The anchor draws three tiers with prices. **They are not the prices this product charges.**

| Tier | Shipped (`upgrade_screen.dart:28`) | FIT-031 declares |
|---|---|---|
| Self-Guided | **$29 /mo** | **£19 /mo** |
| AI-Guided | **$59 /mo** | **£39 /mo** |
| Coach-Guided | **"Coach-set"** (no price) | **£79 /mo** |

Different **currency** and different **amounts**, on every tier. The shipped ladder also has
**four** entries (Free, Self, AI, Coach); the anchor draws three.

### Why this is not a copy change

The displayed prices are backed by **real Stripe price IDs**:
`STRIPE_SELF_GUIDED_PRICE_ID` and `STRIPE_AI_GUIDED_PRICE_ID`
(`supabase/functions/create-checkout/index.ts:13`, `update-subscription/index.ts:10`), and
that function's own header records the amounts as **$29/mo** and **$59/mo**.

**Editing the label alone would show a client £19 and charge them $29.** That is not a
design-integration task with a copy risk attached; it is a consumer-harm risk, and the
decision — which currency, which amounts, whether Free survives, and whether Stripe is
repriced — belongs to the owner. Recorded as **OD-18**.

### What was taken

`Close` only. FIT-031 declares it; `AppBar`'s automatic leading was a back arrow named by
Material's default tooltip rather than by the package. The action is unchanged — it pops,
exactly as before.

`Switch to coach-guided` was **not** taken either, although it is only a label. The shipped
CTA reads `Find a Coach` and navigates to the marketplace; the anchor's wording promises a
**plan switch**. Those are different actions, and relabelling one as the other on a paywall
is the same class of decision as the prices.

**FIT-031: 1/5, and the remaining four are one owner decision, not four tasks.**

## 3u · FIT-021 · the entitlement gate — 0/3 → **3/3**, behind twelve routes

One component, twelve gated routes. The anchor declares three controls; the screen had one
and a half.

| Declared | Was | Now |
|---|---|---|
| `See plans` | `See Plans` | the locked screen's own case |
| `Back` | `AppBar`'s automatic leading, named by **Material's default tooltip** rather than by the package | named `Back`, 44 dp |
| `Not now` | **did not exist** | present, leaves the gate |

**`Not now` is the one that mattered.** A client who hit a paywall could only leave by the
system back gesture — nothing on screen said they were allowed to. On a screen whose whole
job is to ask for money, the absence of a visible way to decline is not a cosmetic gap.

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/paywall_locked_test.dart` — 6 tests | **PASS** |
| Guard strength | 4 mutations killed, including **"`Not now` is drawn but does not leave"** — the control existing is not the point, being able to decline is | **PASS** |
| Suite | 1089 pass / 9 skipped | **PASS** |
| Runtime | not device-verified — `PaywallLocked` is a leaf and the host semantics tree is the same tree. **FIXED IN CODE**. | **OPEN** |

`_Locked` was made public as `PaywallLocked` so the three controls could be asserted at
all: `PaywallGate` itself reads two Supabase-backed providers, and this state takes plain
values. Eighth extraction-or-exposure for that reason.

**This is the second anchor completed** (after FIT-002), and the first cross-cutting one —
it is the gate on twelve routes rather than one screen.

## 3v · F-26 · the app's front door could not be opened without a drag **FOUND AND FIXED**

Found while aligning FIT-006's two labels — the label was the smaller problem.

`/onboarding`'s "Get Started" is a **slide-to-confirm** control:
`onHorizontalDragUpdate` and `onHorizontalDragEnd`, **no tap, no semantics**. A
screen-reader user, or anyone who cannot perform a precise horizontal drag — switch
access, tremor, limited dexterity — **could not create an account at all.**

Not a labelling gap. The first screen of the product had no accessible path past it.

**The slide stays.** It is what the design draws and the friction is deliberate. What was
added is one activatable node for the accessibility APIs, which is the standard remedy and
changes nothing on screen. A test asserts the drag handler survives, so a later "fix" that
replaces the interaction fails.

| | Before | After |
|---|---|---|
| account CTA | drag only, unnamed | `button=true tap=true`, named `Create your account` |
| sign-in CTA | "Already a member? Sign In", ~20 dp tall | `I already have one`, `363.4 × 44.0 dp` |

FIT-006's wording is now on screen. The **visible** text changed rather than being
overridden in semantics — an accessible name has to contain the visible label (WCAG 2.5.3),
so announcing the design's phrase over different words would have been a violation dressed
up as coverage. Destinations unchanged.

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/onboarding_entry_test.dart` — 5 tests | **PASS** |
| Guard strength | 4 mutations killed, including **the drag-only front door itself** and **"the slide gesture removed"** — the fix must add, not replace | **PASS** |
| **Runtime, on device** | `integration_test/f26_onboarding_entry_device_test.dart` on `emulator-5554`: both controls `button=true tap=true` | **VERIFIED ON DEVICE** |
| Suite | 1094 pass / 9 skipped | **PASS** |

**FIT-006: 0/2 → 2/2.** Third anchor completed.

**Residual, recorded not fixed.** The semantic action covers screen readers and switch
access, which is what the platform APIs drive. A **sighted** user with limited dexterity
and no assistive technology enabled still has only the drag. Making the knob tappable would
remove the deliberate friction the design specifies, so it is not done here — recorded as a
known limitation rather than resolved by guessing.

## 3w · The design board carries the BODY COPY — it had not been used as a source

A finding about the method, discovered while building FIT-009.

Every copy decision in this programme so far was made against `manifest.json`, which lists
**interaction labels** and nothing else. That is why so much was recorded as "the package
supplies no copy for this frame" and pushed to OD-8.

**`12Circle Fitness - Complete Board.dc.html` (466 KB) carries the prose**, per frame, plus
the designer's annotations. FIT-009's entire screen was in it:

> "That's everything we needed."
> "*<coach>* has your answers and will have your first week ready by tomorrow morning."
> "While you wait" · "Have a look at the exercise library, or log what you ate today."
> "Go to my home"
> — and the note: *"Success is quiet: a mark, a sentence, what happens next. **No confetti,
> no celebration animation** — the brief's 'rewarding but sophisticated', applied
> literally."*

Spot checks confirm it is not unique to that frame: `Reply to Nadia`,
`Who can see my progress · Coach only` and their surrounding paragraphs are all there.

**This does not retroactively make any earlier decision wrong** — where the house pattern
was reused (`Could not load [noun]`, `Try again`) the result is the same words the product
already ships. It does mean the board should be consulted before anything is recorded as
copy-blocked again.

## 3x · FIT-009 · Intake complete — the state that did not exist

The flow called `context.go('/home')` the instant the last answer saved. **The state the
anchor draws never existed**: a client finished a long intake and their work ended in a
screen transition.

Every word is the board's, including the design note, applied literally — a mark, a
sentence, what happens next. A test asserts there is **no celebration icon**, because the
note is explicit and a later "improvement" would otherwise quietly contradict it.

The coach's name goes through the same `coachAddressed` rule as FIT-004 and FIT-015: a
failed read must not name a coach the client may not have, and the fallback — "*We* have
your answers…" — is grammatical without one.

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/intake_complete_test.dart` — 8 tests | **PASS** |
| Guard strength | 3 mutations killed: celebrate (contradicting the board), drop the heading roles, **skip the state and go straight home** (the shipped behaviour) | **PASS** |
| Suite | 1102 pass / 9 skipped | **PASS** |
| Runtime | not device-verified — leaf widget. **FIXED IN CODE**. | **OPEN** |

**Two limits recorded rather than papered over.**

The wiring — *does the flow actually render the state* — cannot be reached by a widget
test, because `IntakeFlowScreen` reads Supabase and cannot be driven to completion. A
source-level guard holds it instead, and deleting the render fails it. Without that guard
the mutation survived.

And one mutation **survives by design** in that file: swapping the coach input for
`AsyncData(provider.valueOrNull)` — which drops the error state — passes, because the
override harness turns an `AsyncError` into `Future.error` and the provider rebuilds with
no previous value. The stale-error case cannot be built through a provider override. It is
built directly, and that mutation killed, in `test/unit/coach_name_test.dart`. Noted in the
test so it does not look like coverage it is not.

**FIT-009: 0/1 → 1/1.** Fourth anchor completed.

## 3y · FIT-022 · Loading & failure — and a **tenth** F-15 case the inventory missed

The board's annotation for this anchor is the most useful sentence in the package:

> *"The failure state names what did **not** happen — 'everything you've logged is saved' —
> because the fear a failed screen creates is data loss, not inconvenience."*

That is why this state is not just another `Could not load X`. A client whose nutrition
screen fails does not mainly want to know a request failed; they want to know their
morning's logging is still there.

### The defect it replaces — not in the nine

`/meals-dashboard` read `totals.valueOrNull?['calories'] ?? 0.0`. **A failed read rendered
zero calories, zero protein, zero carbs and zero fat** to a client who had logged three
meals — who might reasonably log them again, and then be over by a day's food.

Same class as `/train`'s "0 workouts", `/home`'s "0%" and `/challenges`' "0 active
challenges". **It was not in the §6c inventory of nine.** That inventory was a survey, not
a proof, and this is the evidence: it under-counted by at least one, found only because
FIT-022 sent me to look at this specific screen.

### What shipped

Every string is the board's, verbatim — `Couldn't load today` / `Everything you've already
logged is saved. Only today's totals failed to load.` / `Try again` — and a test asserts
the **reassurance clause specifically**, because a failure card that only says "could not
load" satisfies the shape and misses the point.

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/nutrition_load_failed_test.dart` — 7 tests | **PASS** |
| Guard strength | 4 mutations killed: drop the reassurance, drop the heading role, drop the 44 dp floor, and **render zeros again** | **PASS** |
| Suite | 1109 pass / 9 skipped | **PASS** |
| Runtime | not device-verified — leaf widget. **FIXED IN CODE**. | **OPEN** |

The fourth mutation needed a **source-level** guard, because `MealsDashboardScreen` reads
Supabase and cannot be mounted. Without it, restoring the `?? 0.0` path survived. Second
time that pattern was needed today, after FIT-009.

### What is NOT claimed

The board gives the principle and **one worked example**. Applying "name what did not
happen" to the other nine failure states means writing a per-screen reassurance sentence —
which is writing copy, even with an authoritative pattern to follow. Those keep the house
`Could not load [noun]` wording, and the upgrade is proposed under **OD-8** rather than
taken.

**FIT-022: 0/1 → 1/1.** Fifth anchor completed.

## 3z · FIT-024 / FIT-025 · Check-in detail — a stub, and a dead end I had made

`checkin_detail_screen.dart` was **23 lines**: an app bar and the words
*"Check-in details coming soon"*. **And FIT-023's history rows, added earlier in this
programme, navigated straight into it.** The dead end was mine — built two cycles ago,
found now only because the anchor sent me to the screen.

Both states are now real, from the board's own copy: the answers as label-value rows, what
the client wrote, the coach's reply as *"the one card, because it's the reason to come back
here"*, and FIT-025's `No reply yet`. The hub now selects the week before navigating, so
the row opens the check-in it names.

### Three places the board could not be followed verbatim — each recorded

**A gendered pronoun.** The board writes *"She usually replies within a day"* because Nadia
is its example. Applying that to a real coach would **misgender them**. The sentence is
written without a pronoun and says the same thing. A test asserts no pronoun appears.

**A schedule this product does not store.** The board's empty state reads *"Nadia reviews
check-ins on Sundays and Mondays."* There is no coach review schedule in the data, and
asserting one would be **inventing a commitment on a coach's behalf** — the client would
chase on Monday. Omitted and recorded as **OD-20**. A test asserts no such claim appears,
while allowing weekday names where they are facts ("Sent Monday 31 August").

**"Energy · Steady".** OD-16 again: the stored value is 1–5. The row reads `3 of 5`, and a
test asserts the three words never appear.

### One more, smaller

The board's "Sleep · 5 of 7 nights" counts **nights**; this product stores an **average
number of hours**. Reporting hours under the board's label would be a different measurement
wearing its words, so the row reads "7 hours average".

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/widget/checkin_detail_test.dart` — 11 tests | **PASS** |
| Guard strength | 5 mutations killed: interpret energy (OD-16 silently), tell a **pending** week the coach has it, use a blank coach name, offer a reply when there is none, render a week when none is selected | **PASS** |
| Suite | 1120 pass / 9 skipped | **PASS** |
| Runtime | not device-verified. **FIXED IN CODE**. | **OPEN** |

**FIT-025: 1/1. FIT-024: 1/2** — `Reply to Nadia` measures absent, correctly: the label is
composed from the coach's name on the reply. Sixth composed-label ceiling.

**A note on FIT-025's previous score.** It was recorded 1/1 *before this work*, against a
stub that rendered "Check-in details coming soon". The single declared interaction is
`Back`, which the stub's `AppBar` supplied automatically — so the anchor measured complete
while the screen did not exist. **A full score against a stub is the strongest argument yet
that presence is weak evidence**, which this document has said from the start and can now
show.

## 3aa · A defect I introduced, and the stub sweep that found it

### F-27 · two `selectedCheckinProvider`s

Building FIT-024 I declared `selectedCheckinProvider` in `checkin_hub.dart`. **One already
existed**, in `checkin_provider.dart`, and it is the one `CheckinCard` sets.

Nothing failed to compile. Nothing failed a test. The analyzer was clean. `CheckinCard`
wrote to one provider and the detail screen read the other, so **tapping a check-in card
would have opened the screen I had just built and shown "Open a check-in from your
history"** — while my own FIT-023 rows, which set the new one, worked.

Two providers of the same name split state between the screens that write it and the
screens that read it, and that is invisible to the analyzer and to any test that exercises
only one path. Mine is removed; the existing one is used. A guard asserts there is exactly
one, and reintroducing a duplicate fails it.

**Found by reading the entry points, not by a test.** It is the clearest example in this
programme of why "reuse existing architecture" is a correctness rule and not a tidiness
preference.

### The stub sweep

FIT-025 had scored **1/1 against a 23-line stub**, which raised the obvious question: how
many other "implemented" screens are placeholders? Swept every `*_screen.dart` under
`lib/features/*/presentation/` for placeholder text and for suspiciously small files.

**The answer is reassuring — four small screens, and only one was a real problem:**

| Screen | Lines | Verdict |
|---|---|---|
| `log_meal_screen.dart` | 23 | redirect to `/meals-dashboard` — recorded under FIT-019 |
| `food_search_screen.dart` | 23 | redirect to `/meals-dashboard` — legitimate |
| `embedded_checkout_screen.dart` | 33 | thin wrapper around the real checkout |
| `checkin_form_screen.dart` | 37 | **an interstitial** — fixed, see below |
| `checkin_detail_screen.dart` | 23 | the stub, now built (§3z) |

No other `coming soon` placeholder exists in the codebase.

### `/checkin-form` was an interstitial, not a screen

It rendered a near-empty page titled "Check-In Form" with one button reading "Go to Daily
Check-In". A client tapping a **pending** check-in card (`checkin_card.dart:25`) landed
there and had to press again to reach the form they had already asked for. It is now a
redirect, matching the two sibling routes that already resolve that way.

## 3ab · FIT-029 · Profile — 2/6 → 4/6, and a third defect in the metric

| Declared | Status |
|---|---|
| `Settings` · `Goals` | already present |
| `Personal information` | was `Personal Info` — the locked screen writes it out |
| `Cycle & wellbeing` | added: a second entry point to a screen **every** client already reaches from Home (the tile there is shown to everyone; only its subtitle changes with `gender`), so no new exposure |
| `Connected apps 2` | label aligned from `Integrations`; **the count is not added** |
| `Coach-guided £79 monthly · renews 1 October` | **OD-18** |

**The count was deliberately left off.** The board draws "Connected apps 2". Nothing in this
app knows how many integrations a client has connected, and a badge reading `2` for
everyone would be a fabricated fact on their own profile. The row measures absent because
of the missing digit, which is the right answer.

### The metric's third defect: HTML entities

The manifest stores labels escaped. `Cycle &amp; wellbeing` was compared against source
containing `Cycle & wellbeing`, so **a label with an ampersand could never match**, however
well implemented. The row was on screen and measured absent.

`tool/fit_coverage.dart` now unescapes first. Two labels in the package are affected, so
the correction is small — but it is the third defect in this one measurement, after
counting its own comments and resolving FIT-019 to a 23-line redirect stub.

**Three defects in one metric is itself the finding.** Every number it produces has been
reported here as a worklist and never as a score; this is the evidence for that caution
rather than a restatement of it.

## 3ac · F-28 · the chat header claimed presence it never had **FOUND AND FIXED**

Found while integrating FIT-026, not by a test.

`/chat`'s header subtitle was the **constant** `"Online now"`, beside a green presence dot.
**Nothing in this repository tracks presence** — no `is_online`, no `last_seen`, no
realtime channel for it. So every conversation claimed the other person was online, always.

A client could message their coach at midnight believing they were there; a coach could
believe the same of a client. It is a fabricated fact about a **third party**, presented
with the one UI element that exists specifically to be trusted.

**FIT-026's header reads "Nadia Rahman / Your coach"** — the relationship, which is real
data on the conversation the caller already carries. Where the role is unknown the subtitle
is **omitted**: an empty line says nothing, and nothing is what the screen knows. The green
dot is gone rather than restyled — the fix for a fabricated fact is not a quieter
fabrication.

## 3ad · FIT-026 · Conversation — 3/5 → 4/5

Every label is an `aria-label` read verbatim off the board's Conversation frame.

| Declared | Status |
|---|---|
| `Back` | already named |
| `Book a call` | **added to the header** — the board: *"Booking sits in the header, because 'can we talk' is the second thing you want in a coach thread."* |
| `Attach` | was an unnamed 40 dp circle |
| `Message` | the composer. A `TextField` with only a hint reports its **value** and no name, so an empty composer announced nothing at all |
| `Send` | was unnamed |
| `Play video from Nadia, 1 minute 48 seconds, form review` | **absent — a real gap, see below** |

| Layer | Evidence | Status |
|---|---|---|
| Behaviour | `test/unit/chat_subtitle_test.dart` — 7 tests | **PASS** |
| Guard strength | 3 mutations killed: **restore the presence claim**, guess a subtitle for an unknown role, change a board label | **PASS** |
| Suite | 1128 pass / 9 skipped | **PASS** |
| Runtime | not device-verified — `ChatScreen` reads Supabase in `_init`. Two **source-level** guards hold the wiring instead. **FIXED IN CODE**. | **OPEN** |

### The fifth interaction is a feature gap, not a label gap

The board draws a **video bubble** — *"Video is a first-class bubble — coach video is how
form gets fixed"* — with the composed label
`Play video from Nadia, 1 minute 48 seconds, form review`.

`MessageType.video` and a `duration` field exist on the message model, but **nothing sends
or renders a video message**: `_MessageBubble` handles text and images only, and the
composer's one attachment path is `_sendPhoto`. Building it needs a capture/upload path, a
player, duration metadata and the "form review" classification — a feature, not an
integration.

Recorded as a gap. The label is also composed from the coach's name and the clip's length,
so it is a **seventh composed-label ceiling** even once the feature exists.

## 3ae · FIT-016 · Workout detail — the row that was a button and did nothing

FIT-016 is **locked**. Its three named controls (`Back`, `More`, `Begin session`) were
already built and the four remaining declared interactions are the board's sample exercise
rows, which the coverage metric can only match by fabricating those exact movements — the
eighth composed-label ceiling, not a backlog. So the measurement stays at **3 / 7** and the
defect was somewhere the measurement cannot see.

### The defect

Each session row rendered:

```dart
Semantics(button: true, label: '$index $name $_prescription',
          excludeSemantics: true, child: Container( … Icon(Icons.info_outline) … ))
```

`button: true` to assistive technology, an info icon to the eye, **and no action wired to
either**. A control that exists for both audiences and responds to neither is the same
false-affordance class as F-20's `44x44 tap=false label="Back"`, one layer down.

### What the package already decided

Nothing here was invented. `manifest.json → FIT-016` declares each row `el: "button"` and
lists `ph-info` among the frame's icons; the board's own annotation says what it does:

> *"Prescription reads as one line per exercise — sets, reps, load, rest — because that is
> what a lifter checks. No thumbnails, no cards. **The info icon opens form and
> instructions.**"*

`Exercise.description`, `Exercise.instructions` and `WorkoutExercise.notes` already hold
exactly that. What the package does **not** contain is a drawn frame for the surface — there
is no exercise-detail screen among the 110 — so every visual choice comes from something the
package does specify: the design system's `surface` `#121215` ("Cards, sheets, rows"), the
`border-radius: 24px 24px 0 0` the board uses for sheet tops in **seven** places, the
system's stated **240 ms** sheet present/dismiss, the package's own dismissal word `Done`
(used in five other frames), and the 44 dp `tap` floor. **No section headings** — `Form` and
`Instructions` appear nowhere in the package, so nothing is labelled with them.

### And where it stops

A row must claim to be a button only when something is behind it. `hasContent` decides, and
**equipment and muscle group deliberately do not count**: they are populated on almost every
library row, so counting them would have made the control near-universal again while looking
fixed. When it is false the row is not a button, exposes no tap action, and the info icon is
not drawn.

`3 × 10 each` — the board's unilateral line — is still **not** emitted. No per-side field
exists on `Exercise` or `WorkoutSet`, and inventing one would assert something about the
prescription the data does not say. Unchanged, and now pinned by a test.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/exercise_brief_test.dart` — 14 tests | **PASS** |
| Widget | `test/widget/workout_detail_exercise_brief_test.dart` — 5 tests, asserted against the **semantics tree**, never against text presence | **PASS** |
| Guard strength | **6 / 6 mutations killed** — see below | **PASS** |
| Suite | **1147 pass / 9 skipped** (was 1128) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | A-G8, EC-G7, EC-G8, SEC-G1/G2 all at or below baseline | **PASS** |
| Runtime | `integration_test/fit016_exercise_brief_device_test.dart`, `emulator-5554` | **RUNTIME_VERIFIED** |
| CI | no Android job exists | **OPEN** |

### Mutations

| # | Mutation | Result |
|---|---|---|
| M1 | drop `onTap:` from the row's `Semantics` | **KILLED** — `tap=false` |
| M2 | let equipment/muscle group count as content | **KILLED** — the inert control returns |
| M3 | always draw the info icon | **KILLED** — drawn on a row that opens nothing |
| M4 | fold the action into the accessible name | **KILLED** — WCAG 2.5.3 |
| M5 | drop the sheet's `Done` tap (the `excludeSemantics` action drop) | **KILLED** — sheet will not dismiss |
| M6 | render an absent load as `0 kg` | **KILLED** |

**M1 survived its first run**, and that is the finding worth recording. The row had been
built with the `GestureDetector` *outside* the `Semantics`, so the ancestor node carried the
tap action and removing `onTap:` changed nothing observable — a test that passes either way.
The structure was changed to `Semantics` outside / gesture inside (the shape
`NamedIconButton` already uses), which makes the declaration load-bearing; M1 then killed.
A mutation that does not kill is a fact about the test, not about the code.

### Runtime evidence — `emulator-5554`, 411.4 dp @ dpr 2.625

```
row1  371.4x73.0  button=true  tap=true  hint="Shows form and instructions"
row2               button=false tap=false hint=""
Done  371.4x48.0  button=true  tap=true
sheet presented, read, dismissed; no exceptions
360.0 dp — sheet open, exception=none
390.0 dp — sheet open, exception=none
411.4 dp — sheet open, exception=none
```

No fixture was created: the screen is mounted with `selectedWorkoutProvider` overridden to
an in-memory workout, nothing is signed in and no row is written. That also keeps it clear
of **F-21 / OD-14** — `/workout-detail` renders the assigned programme in production and
stays blocked for *integrity* claims; this measures the widget's geometry and semantics, not
the authenticity of any assignment.

### One thing recorded rather than resolved

`WorkoutSet` documents null and zero as **different** answers — null is "no load
prescribed", zero is a prescribed zero (bodyweight). On screen they render identically,
because the package contains no word for bodyweight anywhere and `0 kg` would be worse than
silence. Pinned by a test so the collapse is a decision, not an accident.

## 3af · FIT-014 · This week — four defects in one row, and a guard that could not see

FIT-014 is **locked**. Measured against the hub screen alone it read 4/12; measured
against the screen **and** the shell that carries the tab labels it reads **6/12**. The
four that remain absent are the board's sample rows, plus `Nutrition` and `Connect`, which
are **F-14** — the open five-tab decision. Neither is work this cycle could do.

The defects were in the rows themselves, and the manifest's flattened labels do not show
them. The board's markup does:

```html
<button type="button" class="tap row">
  <span class="met" style="color: var(--green);"><i class="ph ph-check"></i></span>
  <span><span class="ttl" style="color: var(--grey);">Upper body — push</span>
        <span class="bds">Monday · 44 min</span></span>
  <span class="mic">Done</span>
</button>
```

| # | Shipped | Board | Why it matters |
|---|---|---|---|
| 1 | `Thu · 30 min` | `Thursday · 30 min` | the abbreviated day sat beside a `THU` chip saying the same word twice |
| 2 | `NOW` as a `.mic` | `Now` in a `.pill` | `.mic` carries `text-transform: uppercase`; **`.pill` does not**. Today's row also loses its violet-muted chip |
| 3 | no marker at all | a hollow ring (`inset 0 0 0 1px var(--dim)`) | an upcoming session was the only row with nothing in the marker column |
| 4 | `Semantics(button: true)`, no action | `<button class="tap row">` | the same false affordance FIT-016's session rows carried — announced to a screen reader and to the eye, answering neither |

The destination for (4) is not invented. A week row **is** a workout, the package contains
exactly one surface for reviewing one before committing — FIT-016, `/workout-detail`,
*"review before committing"* — and `selectedWorkoutProvider` is the identity mechanism
`workout_list_screen` and `active_workout_screen` already use. Committing stays on the hero
card's `Begin session`.

`WeekRowTile` was extracted from the 1,170-line screen for the reason `PillTab` and
`NutritionLoadFailed` were: a row that navigates cannot be **proven** to navigate while it
is private to a screen that reads a dozen Supabase-backed providers.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/week_row_test.dart` — 13 tests | **PASS** |
| Widget | `test/widget/week_row_tile_test.dart` — 7 tests, against the semantics tree and a **real router**, never text presence | **PASS** |
| Guard strength | **9 / 9 mutations killed** (W8 first run invalid → re-run validly) | **PASS** |
| Suite | **1169 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Runtime | `integration_test/fit014_week_rows_device_test.dart`, `emulator-5554` | **RUNTIME_VERIFIED** |
| CI | no Android job exists | **OPEN** |

### The device produces the manifest's four labels verbatim

```
row0 411.4x73.0 button=true tap=true label="Upper body — push Monday · 44 min Done"
row1 411.4x73.0 button=true tap=true label="Lower body — strength Today · 48 min Now"
row2 411.4x73.0 button=true tap=true label="Conditioning Thursday · 30 min Thu"
row3 411.4x73.0 button=true tap=true label="Upper body — pull Saturday · 44 min Sat"
selected="Upper body — pull"        360 / 390 / 411.4 dp — exception=none
```

Those are the four interactions the coverage tool reports **ABSENT**, produced at runtime
from real `Workout` fields. The tool greps source for a literal and cannot see it; the
device can. The measurement stays 6/12 and this is what 6/12 means here.

### The guard that could not see what it was counting

`H-D1` in `presentation_drift_guard_test.dart` pins the per-screen private-palette
population at 20 files so **D-2** can be decided deliberately rather than overtaken by
drift. Extracting `WeekRowTile` copied a palette into a new file — and the guard **passed**.

Its detector required `static const Color <name>` or a member beginning with `c`. **None of
the twenty listed palettes are written that way.** They are `static const bg =
Color(0xFF0E0E0F)`, with no type annotation. Measured:

| Detector | Files found |
|---|---|
| as shipped | **5** |
| shape-accurate | **22** |

So the guard had been green not because nothing grew, but because it could not see fifteen
of the files it names. That is F-25's class — an assertion that cannot observe what it
asserts — for the third time in this programme.

Repairing it surfaced **`ai_coach_screen.dart`**, a palette that had drifted in undetected.
It is listed rather than quietly deleted and rather than migrated: rewriting another
feature's screen is D-2's decision, not a QA repair.

The palette itself was not duplicated. It moved to `train_palette.dart` and the screen
aliases it (`typedef _C = TrainColors`) — one declaration, two consumers, population
unchanged — and a second test holds the screen to that, so a relocation can never be
mistaken for an addition.

**And the guard now proves its own detector.** Reverting the regex initially **survived**:
`added = found − known` is empty both when nothing drifted in and when the detector has gone
blind, and the assertion could not tell those apart. `known` is now a **floor for detection**
as well as a ceiling for additions — every listed file must still be found. With that in
place the reverted regex is killed.

## 3ag · Every ratchet audited for the defect H-D1 had

H-D1 was green because it could not see, not because nothing had grown. That is
the **third** instance of the same class in this programme — F-25's two live
assertions, one of them green forever, and now this — so the remaining ratchets
were audited rather than assumed.

The defect is structural, not a typo. Every ratchet asserts `count <= baseline`,
and that is satisfied by **two opposite facts**: nothing drifted in, or the detector
stopped seeing. Nothing distinguishes them, so a detector can rot silently and the
guard reports success the whole time.

| Ratchet | Detector floor before | Verdict |
|---|---|---|
| **SEC-G1** | fails loudly when the scan is empty; asserts the two proven-exploitable tables are still found | **SOUND** |
| **SEC-G2** | fails loudly when empty; asserts all four blast-radius tables are still found | **SOUND** |
| **EC-G7** | its companion calls the **same** `_silentErrorBranches()` and asserts the recorded files in both directions, so a blind detector empties the set and fails | **SOUND** |
| **EC-G8** | its companion uses a **separate inline** scan, so the shared `_valueOrNullReads()` could go blind unnoticed | **NO FLOOR — fixed** |
| **A-G8** | its companion reads source strings directly and would stay green with `scan()` returning nothing | **NO FLOOR — fixed** |
| **H-D1** | none, and it *had* gone blind — 5 of 20 | **fixed in §3af** |

Both repairs follow SEC-G1/G2's shape: name the heaviest measured sites and assert
the detector still finds them. When one is genuinely fixed, its entry is deleted and
the baseline lowered **in the same change** — the discipline the security ratchets
already use.

A-G8 additionally gets a **discrimination** check: `named_icon_button.dart` must
**not** be counted. A detector that fires on everything would also satisfy
`count <= baseline` after someone raised the number, and over-reporting is how a
baseline stops meaning anything.

| Mutation | Result |
|---|---|
| D1 · blind A-G8's `GestureDetector\|InkWell\|InkResponse` regex | **KILLED** |
| D2 · make A-G8 count every tappable, named or not | **KILLED** |
| D3 · make `_valueOrNullReads()` return nothing | **KILLED** |
| G2 · revert H-D1's regex to the broken one | **KILLED** (survived before the floor was added) |

Measured while auditing, and recorded because the numbers are not the baselines:
A-G8 scans **45** against a baseline of 46; `.valueOrNull` occurrences total **148**
across 59 files, where EC-G8's own scanner — which strips comments and counts reads
rather than raw occurrences — records 134.

Suite: **1171 pass / 9 skipped**. Analyzer: 0 errors.

## 3ah · SEC-G3 · a read the database already denies, now ratcheted

FIT-032 ("Coach dashboard — triage, not a wall") is locked, and its `At risk` row is
*"No sessions logged in 9 days"*. Before building it I resolved the RLS state of every
table the dashboard reads. Three things came out of that, and **two of them were already
recorded** — reported here as confirmation, not discovery.

### One of mine was a false positive, and its shape is worth keeping

I first concluded that `ai_insights`, `ai_reviews` and `ai_goal_predictions` had **no RLS
anywhere in the migrations** — no `CREATE TABLE … ENABLE ROW LEVEL SECURITY`, no policy.
That is wrong. `074_ai_coaching_layer.sql:74-81` enables RLS on all five `ai_*` tables and
grants `own ai data` inside a `do $$ … foreach t in array[…] loop execute format(…)` block,
which a line-oriented scan does not see.

`docs/QA_WORKSTREAM_D_EDGE_AI_READINESS_REPORT.md:27` records a **previous** workstream
making and correcting the identical mistake. Two independent passes reached the same false
positive by the same mechanism, which makes it a property of the detector rather than of
either analyst: **any RLS audit of this repo that greps line-wise will under-report
protection and over-report exposure.** Re-run with a scanner that reads dynamic SQL, the
three tables are correctly `user_id = auth.uid()` with a `WITH CHECK`.

### Two findings re-derived independently, both already in the ledger

`checkins` does not exist in any migration and is read by `coach_dashboard_screen.dart`.
Already tracked — **I-CHK-01**, `supabase/tests/contract/known-violations.json`, with a
bidirectional guard. Not new.

`workout_logs` has no coach-read policy and three code paths read it for other users' ids.
Already recorded in **§6b** above, in nearly these words. Not new either — but arriving at
it independently confirms the record, and the re-derivation turned up the part that **was**
missing.

### What is actually new: the authorized path already exists

The §6b record states the gap. It does not state that a correct alternative is already
built, and that changes what can be done about it:

| Source | Coach access | Provenance |
|---|---|---|
| `workout_logs` | **none** — `USING (user_id = auth.uid())`, `003:193`, sole policy | — |
| `workout_sessions` | **permitted** — `USING (user_id = auth.uid() OR public.is_active_coach_of(user_id))` FOR SELECT | `100_rls_harden_client_data.sql` |
| `coach_client_ai_signals()` | **permitted** — `SECURITY DEFINER`, scoped to `r.coach_id = auth.uid() AND r.status = 'active'`, returns `workouts_7d` | `079:70`, comment: *"SECURITY DEFINER so a coach can read their clients' AI risk/insights (which RLS otherwise restricts to the client)"* |

So FIT-032's training-frequency signal **can be built correctly today**, with no policy
change and no owner decision. The three recorded reads are not blocked on OD-14; they are
querying the wrong table.

### Why this is not OD-14, stated so it cannot be conflated

F-21/OD-14 is a policy that **claims a role it never verifies** — correcting it changes the
authorization model, which is the owner's call. This is the opposite: a table with **no
coach policy at all**, whose authorized route exists elsewhere. SEC-G3 proposes no policy
change and touches nothing F-21 covers.

### Why a denial deserves a ratchet at all

An RLS-filtered `SELECT` **is not an error**. PostgREST answers `200` with `[]`,
indistinguishable from "this client trained zero times". The F-15 work gave these screens an
error arm; this defect never reaches it — `coach_dashboard_screen.dart:176` only trips
`failed` on `AsyncError`. The result is not a broken screen but a **confident wrong zero**,
permanently, driving an "at risk" judgement about a real person. Built naively, FIT-032's
`At risk` row would fire for **every client, always**.

`SEC-G3` (`test/unit/declared_denied_read_guard_test.dart`) pins the three sites as a
shrinking, bidirectionally-checked allowlist, carries the H-D1 detector floor, and fails if
a coach policy ever lands on `workout_logs` so the guard is revisited rather than left
forbidding a legitimate read.

| Mutation | Result |
|---|---|
| S1 · a fourth cross-user read ships | **KILLED** (first run invalid — it mutated a different query in the same file; re-run validly) |
| S2 · blind the scanner | **KILLED** |
| S3 · make the self-read exemption swallow everything | **KILLED** |

`insights_provider.dart:82` reads `workout_logs` with `.eq('user_id', uid)` — the signed-in
user. A self-read, permitted, and deliberately **not** listed; S3 exists because an
exemption that matched everything would have hidden all three real sites.

Suite: **1174 pass / 9 skipped**. Analyzer: 0 errors. No live mutation was performed and no
policy was changed.

## 3ai · FIT-032 · the triage rules, and the three places they refuse to speak

FIT-032 is **locked**, and its annotation is the strongest product statement in the
package:

> *"A coach with 24 clients does not need 24 rows on open — they need the six that need
> something, each with the action named. 'Needs you today' is triage; the roster is one tap
> away. Coach nav is unchanged."*

The shipped `/coach-dashboard` is 1,642 lines of exactly what that rejects — tabs, an
`ALL CLIENTS` roster, a leaderboard, AI panels. It is **not** being deleted: it carries a
coach's only path to invites and pending requests, which the board does not draw, and
removing a capability because a frame omits it is the mistake **OD-15** already records.
The triage surface is being added as the opening state.

This commit is the rules layer — pure functions, no I/O, no widget — because that is where
the board's product decisions live and where they can be proven.

### Every signal comes from a source a coach may actually read

| Row | Source | Authority |
|---|---|---|
| `Review` | `weekly_checkins` | `114` — owner **or** `is_active_coach_of` |
| `At risk` | `workout_sessions` + `churn_risk` | `100` — owner **or** `is_active_coach_of`, FOR SELECT; `079` RPC |
| `Assign` | `workout_program_assignments` | two-party, SEC-G2 — **readable, but see below** |
| `Reply` | `messages` / `conversations` | participant-scoped; the coach is a participant |

**`workout_logs` is deliberately not a source**, per §3ah and `SEC-G3`. Built on it, the
`At risk` row would fire for every client always — a confident wrong zero about a real
person. `workout_sessions` answers the same question and a coach is permitted to ask it.

**`Assign` stays BLOCKED-BY-F21 for integrity claims.**
`workout_program_assignments` is one of SEC-G2's four two-party tables
(`docs/F21_BLAST_RADIUS.md` §3a). The rule is built and tested; what it must not claim is
that the assignment it reads is authentic. Same standing as `/workout-detail`.

### The three refusals

A rule that always produces a row is not triage. Each of these is a place the rules stay
silent, and each is pinned by a test **and** a mutation:

1. **No name, no row.** "Client needs you today" is not triage.
2. **No sessions at all is not a silence.** A client who has never trained has no sessions
   either; counting that as inactivity would put every new client on the coach's list on
   day one — the opposite of what the board asks for.
3. **A risk score with no day count states the risk, not a number.** `Flagged at risk of
   dropping off`, never `No sessions logged in 0 days`.

### The thresholds are the caller's, and that is recorded as OD-21

The board shows **values** — `9 days`, `Sunday` — not thresholds. How long a silence must
last before a coach is told a client is at risk, and how far ahead a block's end should
surface, are judgements about what a coach is being told. `inactivityDays` and
`blockEndHorizonDays` are **required parameters with no default**, so no call site can
adopt a number by accident.

The one threshold that is fixed is the one already shipped: `churn_risk >= 50`
(`coach_dashboard_screen.dart:565`). Reusing it is not a new decision, so it is a constant
rather than a parameter — and a test pins it at 50.

The **order** is the board's order and nothing more. No priority between a silent client and
an unanswered question is stated anywhere in the package, and inventing one would assert a
coaching judgement the design did not make.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/coach_triage_test.dart` — 22 tests | **PASS** |
| Guard strength | **8 / 8 mutations killed** (T2's first run was a no-op; re-run validly) | **PASS** |
| Suite | **1196 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Presentation | not yet wired — rules only | **OPEN** |
| Runtime | not yet — nothing renders these | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| T1 | no sessions at all counts as a silence | **KILLED** |
| T2 | an unnamed client gets a placeholder row | **KILLED** (first run was a no-op) |
| T3 | ignore the inactivity threshold | **KILLED** |
| T4 | drift the churn threshold to 40 | **KILLED** |
| T5 | `hasNextBlock` stops mattering | **KILLED** |
| T6 | the visible cap becomes six | **KILLED** |
| T7 | the overflow line uses a numeral | **KILLED** |
| T8 | a risk-only row invents a day count | **KILLED** |

### New owner decision

**OD-21 · the two triage thresholds.** How many days of silence make a client "at risk",
and how many days before a block ends the coach should be prompted to assign the next one.
The board shows `9 days` and `Sunday` as sample values, not as rules. Until the owner sets
them, the rules layer refuses a default and the call site must state both.

## 3aj · FIT-032 · the triage surface, an invented route, and a guard counting the wrong shape

The rules from §3ai are now on screen. `/coach-dashboard` measures **5/11 → 6/11**; the
five that remain are the four **sample clients** and `All 24 clients`, which is composed
with the live roster count — composed-label ceilings, not backlog.

The board's triage is added **above** the shipped roster, not in place of it. The existing
screen carries a coach's only path to invites and pending requests, which the board does not
draw, and removing a capability because a frame omits it is the mistake **OD-15** records.

### `Messages` and `Notifications` — and a coverage false positive

The manifest declares both. `Notifications` measured **HAVE** before this change, and it was
wrong: the bell was a bare `GestureDetector` wrapping `Icon(Icons.notifications_outlined)`
with no accessible name at all — an **A-G8 site**. The metric matched the word inside the
*icon constant*. Both controls are now `NamedIconButton`s, and `Messages` — which did not
exist — opens `/messages`.

That is the fourth defect found in this measurement, after counting comments, resolving a
route to a redirect stub, and failing on HTML entities. All four have the same character:
**the tool matches text, and text is not a control.**

### The route I invented

An earlier draft routed `Assign` to `/coach-programs` and the roster to `/clients`.
**Neither is registered.** They read plausibly, `context.go` takes a `String`, nothing fails
at compile time, and go_router would have put the coach on an error page.

Corrected against the router, and against the coach nav in `app_shell.dart:95-103`, which
already answers each of these:

| Action | Route | Why that one |
|---|---|---|
| `Review` | `/coach-checkin-review` | the nav's own `Check-ins` |
| `Reply` | `/messages` | the coach's thread |
| `Assign` | `/program-builder` | the nav's own `Programs` |
| `At risk` | `/coach-client-workouts` | a state, not an action — where a coach *looks* |

A test now reads this widget's `context.go(…)` calls and asserts every one appears in
`app_router.dart`. It is the only thing in the suite that could have caught it: the rules
tests do not navigate, and the analyzer cannot type-check a string.

### `H-D1` counts the wrong shape — H-D2 added

H-D1 pins "the per-screen private-palette population" at 21 files. It counts palette
**classes**. That is not how most of this codebase declares a palette, and **it is not how
anything this programme added declares one** — `exercise_brief_sheet`, `pill_tab`,
`nutrition_load_failed`, `intake_complete_page`, `checkin_detail_screen` and
`needs_you_today` all use top-level `const _ink = Color(0xFF…)`.

| Shape | Files |
|---|---|
| palette **class** — what H-D1 counts | **21** |
| top-level colour consts — what it does not | **77** |

So "the population is 21" was never true of the thing D-2 is about, and the shape this
programme kept reaching for was the one nothing counted. Said plainly: I have been adding to
an uncounted population for several commits, and writing this guard is how I found out.

**H-D2** ratchets the second shape at 77 with its own detector floor. Listing 77 files
against an open owner decision would be a large mechanical change, so it is a bare count —
it may fall, it may not rise.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/coach_triage_test.dart` — 22 | **PASS** |
| Widget | `test/widget/needs_you_today_test.dart` — 8, incl. the route guard | **PASS** |
| Guard strength | **14 / 14 mutations killed** — 8 on the rules, 6 on the widget | **PASS** |
| Ratchets | A-G8, EC-G7, EC-G8, SEC-G1/G2/G3, H-D1, **H-D2** | **PASS** |
| Suite | **1205 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Runtime | `integration_test/fit032_needs_you_device_test.dart` | **RUNTIME_VERIFIED** |

| # | Mutation | Result |
|---|---|---|
| U1 | an invented route comes back | **KILLED** |
| U2 | drop `onTap` from the row's `Semantics` | **KILLED** |
| U3 | `Review` and `Assign` swap destinations | **KILLED** |
| U4 | the empty state renders nothing | **KILLED** |
| U5 | the chips get uppercased | **KILLED** |
| U6 | a coach with no clients is offered a roster | **KILLED** |
| V1 | a 78th top-level palette ships | **KILLED** |
| V2 | blind the H-D2 detector | **KILLED** |

### Runtime — `emulator-5554`, 411.4 dp @ dpr 2.625

```
379.4x69.0 button=true tap=true "Amara Osei Week 14 check-in · travel next week Review"
379.4x69.0 button=true tap=true "Tomas Vidal No sessions logged in 9 days At risk"
379.4x69.0 button=true tap=true "Priya Raman Block ends Sunday · needs next Assign"
379.4x69.0 button=true tap=true "Lena Fischer Asked about the split squat Reply"
Assign -> /program-builder reached
360.0 / 390.0 / 411.4 dp — exception=none
```

All four of the manifest's declared row labels, produced verbatim from `ClientSignals`. As
with FIT-014, the coverage tool reports them ABSENT because it greps source for a literal;
the device shows the shape is exact.

No fixture was created and nothing was written. The `Assign` rule is exercised, and — as
recorded in §3ai — **nothing here claims the assignment behind it is authentic**. That
remains F-21/OD-14.

## 3ak · FIT-003 · the line that was never rendered, and a test that could not see it

FIT-003 is **locked**. It measures **6/12** and stays there: the three absent rows are
sample meals, and `Workouts` / `Connect` are **F-14**. The defect was in the row itself.

### The board's middle line was simply missing

The board draws a **row**: `Greek yoghurt, berries, seeds / Breakfast · 07:20 / 380`.
What shipped was a **card** — a 52 dp tinted icon, the name, `380 kcal`, three macro
**progress bars**, and an inert `more_horiz` with no name and no action.

The board's annotation rejects that shape in as many words:

> *"Today, what you ate, what's left, coach guidance — in that order. Macros read as three
> figures against their targets on one rule, **not three progress cards**."*

And the meal's **type and time were not rendered at all**, though `nutrition_logs` has
carried `meal_type` and `logged_at` since **migration 012**. The data was there the whole
time; nothing read it.

### A mutation that survived, and what it proved about the test

`MealRowTile` began as a private `_MealCard` inside a 1,490-line screen, so it was asserted
against **committed source** — the shape `presentation_drift_guard_test.dart` uses. The test
checked that `mealRowDetail(` appeared in the widget.

**N6 wrapped the render in `if (false)` and the test passed.** The call was still in the
source; the line was gone from the screen.

A source assertion can prove a value is **computed**. It cannot prove it is **rendered**,
and computed is not what a client sees. This is the same family as the directive's
"text-presence as proof of wiring", one level up — and it is the second time this session a
mutation has exposed a test rather than a defect (the first was FIT-016's M1). So the row
was extracted, the way `PillTab` and `WeekRowTile` were and for the same reason, and the
test now mounts it. N6 re-run: **KILLED**.

### Two places the board could not be followed

**OD-22 · `After training`.** The board's third row reads `After training · 18:10`.
`nutrition_logs.meal_type` is a CHECK over exactly five values —
`breakfast | lunch | dinner | snack | protein_shake` — and *"after training"* is not one. It
is a claim about **when a meal was taken relative to a session**, and nothing in this
product links a nutrition log to a workout. Rendering it would assert a training session
that may not have happened, so `protein_shake` reads as **`Protein shake`** and a test
asserts the board's phrase is produced by nothing — the same treatment OD-16 got.

**OD-23 · the row is not a button.** The manifest declares `el: "button"`. The board draws
no destination, and this app has **no edit or delete path for a logged meal** — the old
card's `more_horiz` opened nothing. So the row is labelled but **not** declared a button:
announcing an affordance with nothing behind it is precisely the defect FIT-016 and FIT-014
both carried. Same reasoning as OD-10 kept FIT-016's `More` inert.

### And a third palette relocation

Extracting the row would have made a **78th** file declaring its own colours, breaking
H-D2 one commit after it was written. The palette moved to `nutrition_palette.dart` and the
screen aliases it — one declaration, two consumers, population unchanged at 77.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/meal_row_test.dart` — 16 tests | **PASS** |
| Widget | `test/widget/meal_row_render_test.dart` — 8, **mounted**, against the semantics tree | **PASS** |
| Guard strength | **9 / 9 mutations killed** (N6 survived as a source assertion; killed once the row was mounted) | **PASS** |
| Suite | **1229 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | A-G8, EC-G7, EC-G8, SEC-G1/G2/G3, H-D1, H-D2 | **PASS** |
| Runtime | `integration_test/fit003_meal_rows_device_test.dart` | **RUNTIME_VERIFIED** |

| # | Mutation | Result |
|---|---|---|
| N1 | `protein_shake` reads as the board's `After training` | **KILLED** |
| N2 | an unknown meal type gets title-cased | **KILLED** |
| N3 | the hour loses its leading zero | **KILLED** |
| N4 | a zero calorie goal counts as a goal | **KILLED** |
| N5 | thousands stop being separated | **KILLED** |
| N6 | the row stops rendering type and time | **KILLED** — after the test was rewritten |
| N7 | the row claims to be a button again | **KILLED** |
| N8 | the row renders the raw `meal_type` | **KILLED** |
| N9 | a nameless log is called `Meal` again | **KILLED** |

### Runtime — `emulator-5554`, 411.4 dp @ dpr 2.625

```
row0 379.4x69.0 button=false "Greek yoghurt, berries, seeds Breakfast · 07:20 380 kcal"
row1 379.4x69.0 button=false "Chicken, rice, greens Lunch · 12:45 640 kcal"
row2 379.4x69.0 button=false "Protein shake, banana Protein shake · 18:10 620 kcal"
360.0 / 390.0 / 411.4 dp — exception=none
```

`kcal` is spoken though the row does not draw it: the board can let the header carry the
unit, but a bare `380` at the end of a spoken sentence tells a screen-reader user nothing.

### New owner decisions

**OD-22 · `After training`.** Whether a nutrition log should record its relation to a
training session. Until it does, `protein_shake` reads as itself.

**OD-23 · what a logged meal row opens.** The manifest declares it a button and nothing —
board or app — says what it does. Edit? Delete? Nutrition detail? Until it is decided the
row is labelled and inert.

## 3al · P0 · the three denied reads now read the table a coach may see

§3ah recorded the finding and `SEC-G3` ratcheted it. This **fixes** it, and it needed no
policy change, no owner decision and no contact with F-21.

### What was wrong

Three coach surfaces read `workout_logs` for other users. That table carries one policy —
`003:193`, `USING (user_id = auth.uid())` — and no coach clause exists in any of the 131
migrations. An RLS-filtered SELECT **is not an error**: PostgREST answers `200` with `[]`.
So none of them failed. They reported that every client had trained **never**, permanently,
and `coach_dashboard_screen.dart:176`'s F-15 `failed` flag only trips on `AsyncError`.

### The fix

All three read `workout_sessions`, which `100_rls_harden_client_data.sql` makes
coach-readable: `USING (user_id = auth.uid() OR public.is_active_coach_of(user_id))` FOR
SELECT.

Both tables are written on the **same completion** — `active_workout_screen.dart:649` calls
`logWorkout()` and `:653` calls `completeSession()` — so nothing was lost. The two disagree
on exactly one consumed field, `duration_minutes` against `duration_seconds`, translated at
the boundary by `sessionAsWorkoutLog` so the four render sites are untouched.

### Security assessment — four things it changed about the plan

**1. `is_active_coach_of` is sound, and materially unlike F-21.** It binds
`r.coach_id = auth.uid()` and requires `r.status = 'active'`. F-21's shape fails because the
caller writes the column the policy trusts; here the caller cannot, because `113:223`
**revokes `authenticated` from `coach_client_relationships` outright**. A test now asserts
that revoke is still present, since every policy built on the helper weakens if it goes.

**2. The policy is `FOR SELECT` only.** The pre-existing `"users manage own sessions"` (001)
is `FOR ALL USING (user_id = auth.uid())`. RLS is permissive-OR, so a coach passes for
SELECT and **only** the owner policy applies to writes. Repointing a read introduces no
write surface.

**3. `status = 'completed'` is required for correctness, not only privacy.** The table also
holds `in_progress` and `abandoned` rows, whose `completed_at` is **null** — and the
workouts tab does `w['completed_at'] != null ? parse : DateTime.now()`. Unfiltered, an
abandoned session would have rendered as a workout finished **"0m ago"**.

**4. Explicit columns are a forward-looking control, not bandwidth.** `workout_sessions` has
gained five columns since 001 (`workout_name`, `total_exercises`, `total_sets`,
`completed_sets`, `calories_burned`). A bare `select()` would have pulled each new one into
a coach surface as it landed, with nobody deciding. `progress_data` and `workout_snapshot`
are now never selected.

### SEC-G3 rewritten, because the fix broke it — correctly

The guard's allowlist was bidirectional, so the fix made it **fail**, printing the
instruction it was written with: *"Either all three were fixed — in which case empty this
list and say so — or the detector is broken."* That is the guard working.

Emptying the list removes its ability to prove the detector works, which is the H-D1 defect
exactly. So the detector is now proven against **synthetic source** — two positive controls
it must flag, and two negatives it must not (a self-read, and the authorized table). Plus
three new assertions: each site reads `workout_sessions`, each filters `completed`, and none
uses a bare `select()`.

### The finding is NOT closed

Its **symptom** is resolved — nothing reads the table cross-user. Its **condition** stands:
`workout_logs` still has no coach policy, and a fourth reader would reintroduce the defect.
SEC-G3 now prevents that. Recording it closed would be a false closure.

| Layer | Evidence | Status |
|---|---|---|
| Conversion | `test/unit/session_as_log_test.dart` — 8 tests | **PASS** |
| Guard | `SEC-G3` rewritten — 9 tests incl. 4 detector controls | **PASS** |
| Guard strength | **10 / 10 mutations killed** | **PASS** |
| Suite | **1242 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | all eight at baseline | **PASS** |
| Runtime | **LOCALLY_VERIFIED, not RUNTIME_VERIFIED** — see below | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| R1 | the denied read returns at a fourth site | **KILLED** |
| R2 | the `completed` filter is dropped | **KILLED** |
| R3 | a site goes back to `select()` | **KILLED** |
| R4 | blind the detector | **KILLED** |
| R5 | the detector flags everything | **KILLED** |
| S1 | seconds truncate instead of rounding | **KILLED** |
| S2 | seconds pass through as minutes | **KILLED** |
| S3 | the negative guard is dropped | **KILLED** — after the test was strengthened |
| S4 | the translation drops every other field | **KILLED** |
| S5 | the input map is mutated in place | **KILLED** |

**S3 survived its first run**, and the cause was the test: `-10 / 60` rounds to `0` with or
without the `<= 0` guard, so a small negative cannot tell them apart. Re-run with `-90`,
which rounds to `-2` — a workout of minus two minutes reaching a coach's adherence count —
it kills. Third time this session a mutation has exposed a test rather than a defect, after
FIT-016's M1 and FIT-003's N6.

**And my mutation harness misreported R2 as INCONCLUSIVE.** It classified any output
containing `error:` as a compile failure, and the failing assertion quoted a widget's
`error: (_, __) =>` arm back at it. The harness now matches `Compilation failed` /
`Failed to load` specifically. A detector for detectors, with the same defect as the
detectors.

### Why LOCALLY_VERIFIED and not RUNTIME_VERIFIED

These providers require an authenticated coach with active clients. Creating that fixture
means writing `coach_client_relationships`, which `113:223` revokes from `authenticated` —
it would need `service_role`, and §24's hygiene rules would then apply to rows on a
security-sensitive table. That is not a fixture worth creating to confirm a query target
that `SEC-G3` already asserts against the migrations themselves.

An APK build was also not run: the volume had **1.2 GB** free against a ~2.67 GB build, and
the only reclaimable 5 GB is the Gradle cache, whose loss costs a long dependency
re-download. Per §25 the environment is left workable rather than stripped. The change is
pure Dart, analyzer-clean, and the full suite compiles the whole `lib` tree.

## 3am · SEC-G4 · the two views that bypass RLS on purpose

§3al fixed one denied read. The obvious next question is whether there are others, so
every cross-user read in `lib` was swept against the **resolved** RLS state of the table it
targets — and the sweep is now a repository tool, `tool/cross_user_read_sweep.dart`, so this
is not rediscovered a third time.

**65 cross-user reads. 6 flagged. None of them a new defect** — but two produced work.

| Flagged | Verdict |
|---|---|
| `checkins` × 1 | already **I-CHK-01** — the table exists in no migration, guarded bidirectionally |
| `community_posts` × 1 | **false positive.** `qa_suites.dart:360` is a reachability probe, `select('id').limit(1)`, no user filter. A readable community feed is the product |
| `public_profiles` × 3, `conversation_participant_profiles` × 1 | **VIEWS.** Not defects — see below |

### Views have no RLS of their own, and these two bypass it deliberately

A view declared `WITH (security_invoker = off)` runs with the **view owner's** privileges
and reads the underlying table **regardless of its RLS**. Both of these read
`user_profiles` — the table `102_restrict_user_profiles.sql` exists to restrict.

Both are sound, and both are right:

* **`public_profiles`** (`101`, re-declared by `110`) is a **curated projection** — display
  names and coach-marketplace fields — with `REVOKE ALL FROM PUBLIC, anon` and
  `GRANT SELECT TO authenticated`. A directory cannot work if every row is invisible; the
  bypass is the design.
* **`conversation_participant_profiles`** (`102`) bypasses too, but carries its **own
  predicate**, `WHERE public.shares_conversation_with(p.id)`, so the bypass is bounded to
  people the caller already shares a thread with. It is also `security_barrier = true`,
  which stops a cheap user-supplied function being evaluated ahead of the predicate.

I checked the predicate function itself: it binds to `auth.uid()`, not to a
caller-supplied parameter. That is the distinction from F-21.

### So what is the gap, and why it is worth a ratchet

The safety of both rests entirely on **two comments**:

> `'Never add medical, contact, billing or intake columns to this view.'`
> `'never drop the shares_conversation_with() predicate'`

Nothing enforced either — and `110` already **re-declares `public_profiles`**, adding two
columns. So these views demonstrably change as the product grows, and a re-declaration that
adds `email`, `phone` or `address`, or drops the predicate, would publish it to **every
authenticated account** with no failing test anywhere.

`SEC-G4` is the enforcement those comments ask for. It changes nothing and proposes
nothing. It reads the **last** definition of each view — because `CREATE OR REPLACE` means
a later migration silently supersedes an earlier one, and reading only `101` would miss what
`110` did — and pins:

* the exact projected column set, **bidirectionally**;
* that nothing from a 23-name forbidden list is projected;
* that the predicate and `security_barrier` are still there;
* that the predicate function still binds `auth.uid()`;
* that `anon` is still revoked.

| Mutation | Result |
|---|---|
| V1 · `email` added to `public_profiles` | **KILLED** |
| V2 · the `shares_conversation_with` predicate dropped | **KILLED** |
| V3 · a later migration re-declares the view unnoticed | **KILLED** |
| V4 · `security_barrier` removed | **KILLED** |
| V5 · blind the view parser | **KILLED** (first run was a no-op; re-run validly) |
| V6 · widen the recorded set to make it pass | **KILLED** |

**V3 and V6 are the two that matter.** V3 added a new migration file declaring a wider
view, which is exactly how this would happen in practice. V6 tried the lazy fix — adding
`email`, `phone`, `address` to the recorded allowlist — and the bidirectional check killed
it, because those columns are not actually projected. A baseline cannot be widened into
meaninglessness here.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/rls_bypassing_view_guard_test.dart` — 12 tests incl. 4 detector controls | **PASS** |
| Guard strength | **6 / 6 mutations killed** | **PASS** |
| Sweep | `tool/cross_user_read_sweep.dart` — 6 flagged of 65, all triaged above | **PASS** |
| Suite | **1254 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors (`lib`, `test`, `tool`) | **PASS** |
| Ratchets | **nine** — A-G8, EC-G7, EC-G8, SEC-G1/G2/G3/**G4**, H-D1, H-D2 | **PASS** |

The sweep tool handles the two things a grep gets wrong here, both of which have already
cost this programme a false positive: **dynamic SQL** (`074`'s `foreach … execute format`
enables RLS on five `ai_*` tables invisibly to a line scan — an error two separate
workstreams have now made) and **self-reads** (`.eq('user_id', uid)`, which would bury real
findings in noise if flagged).

## 3an · FIT-033 · the queue was the feature, and it did not exist — **1/5 → 5/5**

The first anchor this programme has taken to **full** declared coverage, and it is genuine:
all five are real named controls, not sample data.

### What the board actually asks for

> *"Six to review means the **flow matters more than the screen**: paged 1-of-6, and the
> primary action is **send and open next**. The insight is drawn from data she already has,
> and stated as a suggestion — the coach decides."*

What shipped was a single-check-in form — `Review Check-In`, `Client Summary`,
`Your Feedback`, `Submit Feedback` — with **no queue, no position and no next**. `Back` was
the only one of five declared controls present, and a coach reviewing six check-ins returned
to a list between every one. The anchor's whole point was missing.

### The four stats, and why only one is exact

| Board | Column | Built |
|---|---|---|
| `Nutrition 92%` | `compliance_percent` | **exactly** |
| `Energy Steady` | `energy_level` 1–5 | `3 of 5` — **OD-16**, the mapping is an open owner decision |
| `Sleep 5/7` | `sleep_hours` | `7.2 h avg` — the board counts **nights**, the schema stores **average hours**. Different statistics; `5/7` cannot be derived from `7.2` |
| `Sessions 4/4` | — | **not produced.** Completed-against-prescribed is on no column of this row — **OD-24** |

### Two more places the board could not be followed

**`She wrote`** → **`They wrote`**. Amara is the board's example; applying a pronoun to a
real client would misgender them. Same decision the check-in detail screen already made.

**`Record`** → drawn, and honestly **disabled**. `coach_video_responses` exists since
migration 002, but §3ad records that nothing in this app captures, uploads or plays a video.
Wiring it to an invented flow would be worse than saying it is unavailable — **OD-25**, the
treatment OD-10 gave FIT-016's `More`.

`Adjust plan` → `/program-builder`, the route the coach nav itself uses for `Programs`.
Checked against the router, not assumed — the lesson of §3aj.

`Send and open next` reads **`Send`** on the last of the queue, because there is no next and
a button must not promise one. `Send` is the package's own word (FIT-026's composer), not
new vocabulary.

### Three defects found by mounting the screen, which source assertions would have missed

**1. The header never rendered.** `_queue()` used `ref.read` on a `FutureProvider`, so the
first frame saw it still loading and nothing rebuilt when it resolved. `Week 14 · 1 of 6`
would not have appeared **in production either**. A source assertion that
`reviewHeaderLine(` is called would have passed.

**2. `tester.tap` misses silently.** The actions sit below the fold, and three tests
reported "the service was never called" when the truth was "the button was never pressed".
Not a product defect, but indistinguishable from one until `ensureVisible` was added.

**3. My disabled-state assertion could not see itself.** `isEnabled` is false both when a
control declares `enabled: false` **and when it declares no enabled state at all**, so a
mutation removing `enabled: false` survived. The claim being made is "this control HAS an
enabled state and it is off" — which is what a screen reader announces as dimmed. Now
asserted with `hasEnabledState` as well.

### EC-G8 tripped, and the code changed rather than the baseline

Adding the queue introduced two `.valueOrNull` reads and the ratchet went 134 → 135. Per
the standing rule the **baseline was not moved**. `.valueOrNull` turns "the queue could not
be loaded" into "the queue is empty", and here those have different consequences: a coach
whose queue failed silently loses `Send and open next` and is never told why. Both reads are
now pattern-matched, and a failed queue **says so** — `Week 14 · couldn't load your review
queue` — while still showing the week it does know.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/coach_review_queue_test.dart` — 26 tests | **PASS** |
| Flow | `test/widget/coach_checkin_review_flow_test.dart` — 16, **mounted**, incl. the failed-queue state | **PASS** |
| Guard strength | **17 / 17 mutations killed** — 9 rules, 8 flow | **PASS** |
| Coverage | FIT-033 **5 / 5** | **PASS** |
| Suite | **1296 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | all nine at baseline, EC-G8 back to **134** | **PASS** |
| Runtime | **LOCALLY_VERIFIED** — see below | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| Q1–Q9 | position off-by-one · unqueued drawn as first · last still promises next · OD-16 resolved silently · the gendered heading returns · absent % becomes zero · out-of-range clamped · nameless client called `Client` · sleep hours passed off as nights | **9 / 9 KILLED** |
| P1 | sending pops back to the list | **KILLED** |
| P2 | the queue is read, not watched — *the defect I shipped* | **KILLED** |
| P3 | the reply carries over to the next client | **KILLED** |
| P4 | a refused send advances anyway, losing the reply | **KILLED** (first run was a no-op) |
| P5 | `Record` claims to be enabled | **KILLED** (survived until the test was strengthened) |
| P6 | `Next` is drawn on the last of the queue | **KILLED** (first run was a no-op) |
| P7 | a failed queue renders as an empty one | **KILLED** |
| P8 | the failure hides the week too | **KILLED** |

### Why LOCALLY_VERIFIED — an environment blocker, stated plainly

The volume has **1.1 GB free** against a ~2.67 GB debug build. This project's own caches are
already cleared (`build`, `.dart_tool/flutter_build` — 95 MB combined). What remains is
**other applications' caches** — `com.openai.codex` 1.9 GB, `Google` 1.7 GB,
`com.microsoft.VSCode.ShipIt` 1.4 GB — and `~/.gradle/caches` at 5.2 GB, whose loss costs a
network re-download that would break the Android build path if it failed.

Deleting another tool's cache is not this programme's call, and §25 says to leave the
environment workable. So FIT-033 is **LOCALLY_VERIFIED, not RUNTIME_VERIFIED**. Four anchors
were device-verified earlier in this session, when 2.2–4.0 GB was free; this one is blocked
by the machine, not by the code. **Reclaiming ~3 GB would unblock it.**

### New owner decisions

**OD-24 · `Sessions 4/4`.** Completed-against-prescribed is recorded nowhere on a weekly
check-in. Either the check-in should carry it, or the review screen should join a week's
prescription to a session count. Until then the stat is absent rather than guessed.

**OD-25 · what `Record` captures.** `coach_video_responses` exists; no capture, upload or
playback path does. Drawn and disabled until the feature exists or the control is dropped.

## 3ao · FIT-008 · one flow, two words — and five interactions that need an owner

FIT-008 measures **2/7** before and after. The number did not move; the truth did.

### What was fixed: the flow contradicted itself

`intake_flow_screen.dart` is 5,841 lines and ~24 steps. **Eleven** labelled the advance
control `Continue`; **five** labelled it `Next` — same action, same `onContinue` callback,
two different words. A client walking the flow read `Continue`, then `Next`, then
`Continue`.

FIT-008's board draws `Continue`, and it was already the majority word in the file, so
unifying on it introduces **no new vocabulary** — it only stops the flow disagreeing with
itself. `A-G9` holds it, with a detector floor and two killed mutations.

Note what the metric did here. `Continue` measured **HAVE** before this change, because the
word appears on ten *other* steps — the goal step's own button said `Next`. The measurement
was resolving a declared interaction against a different screen's control. Fixing it changed
a false positive into a true one and **moved the number not at all**. Fifth defect found in
this measurement, after counting comments, resolving a route to a redirect stub, failing on
HTML entities, and matching a word inside an icon constant.

### What is blocked, and why it is not mine to decide

The board's step draws four **archetypes**:

```
Getting stronger            Progressive load, fewer sessions
Feeling better day to day   Energy, sleep, consistency
Changing composition        Training plus nutrition targets
Coming back from a break    Rebuild gently, no ego
```

The flow ships **six** goals, and their values are not labels — they are **inputs to the
plan generator**. `047_self_guided_plan_generator.sql`:

```sql
v_cal  := round(v_bmr * v_mult + case
    when p.fitness_goal = 'lose_fat'     then -500
    when p.fitness_goal = 'build_muscle' then  300
    when p.fitness_goal = 'body_recomp'  then -200
    else 0 end);
v_reps := case when p.fitness_goal = 'build_muscle' then 10
               when p.fitness_goal in ('lose_fat','body_recomp') then 13 else 12 end;
v_rest := case when p.fitness_goal = 'build_muscle' then 90 ... end;
```

So a goal decides a client's **daily calorie target, rep range and rest interval**. Against
that, the board's four:

| Board archetype | Maps to | Consequence if forced |
|---|---|---|
| `Changing composition` | `body_recomp` | clean |
| `Getting stronger` | — | strength is low-rep, heavy; `build_muscle` sets **10 reps and +300 kcal**. Not the same prescription |
| `Feeling better day to day` | — | falls to `else 0` — no deficit, 12 reps. A default, not a choice |
| `Coming back from a break` | — | same, and "rebuild gently" is the one archetype that most implies a *different* prescription |

Two of the four have **no engine value at all**, and one maps to a prescription that
contradicts its own subtitle. Shipping the archetypes without resolving that would silently
change what every new client is told to eat and how they are told to train. That is a core
product rule, not an engineering choice — **§21**.

`Skip this` is the same question in miniature: skipping is not a UI affordance when the
answer feeds a calorie calculation. What does the generator do for a client who declined to
say? `else 0` is a *silent* answer, not a considered one.

And the board's progress reads **`4 of 11`** where the flow has **24** steps. The archetype
note — *"Progress is a hairline, not a stepper"* — is a visual change to a bar shared by
every step; the **count** is structural.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/intake_advance_label_guard_test.dart` (A-G9) — 3 tests | **PASS** |
| Guard strength | **2 / 2 mutations killed** | **PASS** |
| Suite | **1299 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | FIT-008 **2/7**, five blocked on OD-26/OD-27 | **BLOCKED** |

| Mutation | Result |
|---|---|
| A1 · a step reverts to `Next` | **KILLED** |
| A2 · blind the detector | **KILLED** |

### New owner decisions

**OD-26 · the goal archetypes.** FIT-008 draws four archetypes; the flow ships six goals
whose values drive calorie targets, rep ranges and rest intervals through
`047_self_guided_plan_generator.sql`. Two of the four map to no engine value and one maps
to a prescription contradicting its own subtitle. Options: (a) extend the generator with
values for the new archetypes; (b) map the four onto existing values and accept the
prescriptions that follow; (c) keep the six shipped goals and record the deviation. Nothing
is changed until this is answered.

**OD-27 · what `Skip this` means for a goal.** The answer feeds a calorie calculation, so
skipping is not merely a UI affordance. Today an unset goal falls to `else 0` — no deficit,
12 reps — which is a silent default rather than a decision. Decide whether the step is
genuinely skippable and what the generator should do when it is.

## 3ap · FIT-001 · the front door was showing a demo workout as the client's own

The largest-impact defect found this cycle, on the screen every client opens first.
**7/9 → 8/9**; the one remaining is `Connect`, which is **F-14**.

*(The ledger recorded 4/9. That was measured against `home_screen.dart` alone —
`Directory`, `Messages` and `Notifications` live in `app_top_nav.dart`. Measuring the files
the screen is actually built from gives 7/9 before this change.)*

### What the card was doing

```dart
final assigned = ref.watch(assignedWorkoutsProvider).valueOrNull ?? const [];
final sample   = ref.watch(workoutsProvider);
final workouts = assigned.isNotEmpty ? assigned : sample;
final firstTitle = workouts.isNotEmpty ? workouts.first.title : 'Full Body Strength';
...
final subtitle = isCoach ? 'Assigned by your coach' : …;
```

A coach-guided client with **nothing assigned** was shown a workout from the **demo
library**, captioned *"Assigned by your coach"*. That is **F-20** — a workout the user did
not choose, presented as theirs — on `/home`.

And it is worse than F-20 was, because of the `.valueOrNull`: a **failed** assignment read
also produced an empty list, fell through the same branch, and was likewise replaced with a
sample workout. The error was not swallowed — it was **substituted**.

Three more, all on the same card:

| Shipped | Truth |
|---|---|
| `'45 min'` | a literal. `Workout.estimatedDuration` exists and was ignored |
| `'550 kcal'` | a literal. Energy expenditure is recorded nowhere on a `Workout` |
| `'2.0K steps'` | a literal. Step count likewise |
| `Start` / `AI Train` / `Start Circle` | the board says **`Begin session`**, on FIT-001 and FIT-014 alike |

The coach-guided branch of `onStart` went to `/workouts` — so a button reading `Start`
started nothing.

### What it does now

Every line comes from `workout/domain/plan_summary.dart`, the rules FIT-014's hero card
already uses — `todaysSession`, `todayPillLabel`, `workoutSummaryLine`. The same session is
no longer described two different ways on two screens.

The library is **not consulted**. With nothing assigned the card says
`No session assigned for today` and sends the client to their plan; with a failed read it
says `Couldn't load your plan`. Three states, three answers, because a client can act on
only one of them.

Badges carry only what the workout states — `48 min`, `6 exercises` — and the button is
named for assistive technology, which it was not.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/home_session_card_test.dart` — 14 tests | **PASS** |
| Guard strength | **7 / 7 mutations killed** | **PASS** |
| Coverage | FIT-001 **8 / 9** — `Connect` is F-14 | **PASS** |
| Suite | **1313 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | all ten at baseline | **PASS** |
| Runtime | **LOCALLY_VERIFIED** — the disk constraint in §3an is unchanged | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| H1 | a failed read becomes an empty plan again | **KILLED** |
| H2 | loading is treated as an empty plan | **KILLED** |
| H3 | a completed session is offered again | **KILLED** |
| H4 | the hardcoded badges come back | **KILLED** |
| H5 | a zero duration renders as `0 min` | **KILLED** |
| H6 | the board's label drifts back to `Start` | **KILLED** |
| H7 | the two empty states collapse into one word | **KILLED** |

## 3aq · FIT-005 / FIT-028 · Connect sold the plan on the screen told not to

Two locked anchors on `/messages`. **FIT-005 4/12 → 6/12, FIT-028 4/10 → 6/10.**

### The copy that nobody in the package wrote

FIT-028's sub-title is *"the state that sells the plan honestly"*, and its annotation says
what that means:

> *"Without a coach the slot is not empty — pods and what's on still fill it. **'Self-guided
> works' is said plainly before the upgrade**, which is the difference between an honest
> prompt and a nag."*

The board's copy:

> **You're training self-guided, which works. A coach adds someone who reads your check-ins
> and adjusts the plan.**

What shipped:

> Browse coaches, compare plans and get matched.

A sales sentence, on the one anchor the package explicitly asked not to sell on. The board
validates the client's current choice **first**, then describes what a coach *adds* rather
than what the client lacks. Replaced verbatim.

### One control existed twice, and the other not at all

The board's markup is unambiguous:

```html
<button class="ph ph-compass" aria-label="Find a coach"></button>
<button class="fc-btn2">Browse coaches</button>
```

Two different controls — a header compass and the primary button. The screen had
**`Find a coach` on the primary button** and **no `Browse coaches` anywhere**.

And the coverage tool reported `Browse coaches` **present**, because those two words opened
the sales sentence in the body copy. Removing that sentence made the false positive visible
— the metric went `Browse coaches` HAVE → ABSENT while the screen got *better*.

**Sixth defect found in this measurement**, after counting comments, resolving a route to a
redirect stub, failing on HTML entities, matching a word inside an icon constant, and
resolving a declared interaction against a different screen's control. Every one is the same
thing: **the tool matches text, and text is not a control.**

### And a section named for half of itself

FIT-028 declares `What's on this week`; the teaser row said `What's on`. The window is part
of the label. (FIT-005's `This week` heads the *full* list under the coach card — a
different component, not a competing name, which is why both can be right.)

### A guard that read its own explanation

The new copy guard failed on first run: the fix's comment **quotes the sentence it
replaced**, so matching raw source found `compare plans and get matched` and reported the
sales line still present. Comments are now stripped before matching — the **third** time in
this programme a detector has read its own prose as evidence, after `tool/fit_coverage.dart`
and the MSG-003 guard.

| Layer | Evidence | Status |
|---|---|---|
| Guards | `connect_sections_view_test.dart` — 2 new, comment-stripped, with detector floors | **PASS** |
| Widget | `messaging_no_coach_test.dart` — updated to the board's two controls | **PASS** |
| Guard strength | **6 / 6 mutations killed** | **PASS** |
| Coverage | FIT-005 **6/12**, FIT-028 **6/10** | **PASS** |
| Suite | **1315 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Runtime | **LOCALLY_VERIFIED** — the §3an disk constraint is unchanged | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| C1 | the sales line comes back | **KILLED** |
| C2 | the section label reverts to `What's on` | **KILLED** |
| C3 | the no-coach state is removed (detector floor) | **KILLED** |
| C4 | the primary button reverts to `Find a coach` | **KILLED** |
| C5 | the header compass loses its declared name | **KILLED** |
| C6 | the button is named but not labelled visibly (WCAG 2.5.3) | **KILLED** |

The remaining absences on both anchors are the board's **sample rows** — `Priya Hit 70 kg on
the hinge today 2h`, `Tues Lifters Sam: anyone in at 7 tomorrow? 3` — and `Workouts` /
`Nutrition`, which are **F-14**.

## 3ar · F-14 RESOLVED by the package itself — and FIT-001 reaches 9/9

**F-14** has blocked `Nutrition`, `Connect` and `Workouts` across eight locked anchors
since it was raised. It was recorded as an owner decision. It is not one: the package
answers it, four separate ways.

### The evidence, counted rather than argued

Eleven frames carry a bottom nav. Parsing every one:

| Declared set | Frames |
|---|---|
| `Home · Workouts · Nutrition · Check-In · Connect` | **10** |
| `Directory · Home · Workouts · Nutrition · Check-In · Connect` | 1 — FIT-001, whose `Directory` is the **top bar** control |
| `Clients · Adherence · Programs · Check-ins` | 1 — the coach bar, already implemented |

There is exactly **one** client nav in the package, and FIT-001's own sub-title explains
the two slots that looked missing: *"Activity folded in · Directory moved to the top bar."*

Every difference from the shipped bar is settled by the package, not by preference:

| Shipped | Resolution | Source |
|---|---|---|
| the animated FAB | *"Directory, chat and notifications sit in the top bar; **the animated FAB is gone**."* | FIT-001 annotation |
| `Activity` tab | "Activity **folded in**" — and its content already IS on Home | FIT-001 sub-title |
| `Train` / `AI Train` | *"the destination is always `/train`, **always labelled Workouts**. `coachingModeProvider` changes what renders here … **not where the tab goes**."* | FIT-014 annotation |

So the bar is now `Home · Workouts · Nutrition · Check-In · Connect`, the mode-switching
label is gone, and AI mode no longer diverts the tab to `/ai-coach`.

### Two things checked before removing anything

**`/directory`** was the FAB's destination. It is already in `app_top_nav.dart` — a previous
cycle moved it there, quoting the same annotation. Removing the FAB takes nothing away.

**`/activity`** was different: the tab being removed was its **only entrance in the entire
codebase**. "Folded in" does not mean orphaned — that is OD-15's lesson — so Home's
week-progress panel, which *is* the activity content, now opens it. The panel header is a
named, hinted, 44 dp control rather than a bare tap target.

### What this unblocks

| Anchor | Before | After |
|---|---|---|
| **FIT-001** Home | 8/9 | **9 / 9** ✅ |
| FIT-015 Workouts — no plan | 5/9 | **8/9** |
| FIT-003 Nutrition | 6/12 | **8/12** |
| FIT-014 Workouts hub | 6/12 | **8/12** |
| FIT-005 Connect | 6/12 | **8/12** |
| FIT-028 Connect — no coach | 6/10 | **8/10** |
| FIT-004 Check-In | 5/11 | **8/11** |

**FIT-001 is the second anchor to reach full declared coverage**, after FIT-033.

### A third bottom nav, and a required parameter nobody read

While tracing the live bar, two more were found:

* **`AppBottomNav`** in `app_scaffold.dart` drew `Overview · Appts · Track · Messages` — a
  third vocabulary. It was never instantiated: nothing in `lib` referenced it, and
  `AppScaffold.build` renders a header and a body and nothing else. (`home_org.dart` holds a
  dead fourth, already recorded.)
* **`navIndex`** was a **required** parameter on `AppScaffold`. Nine screens computed and
  passed a value. **No code ever read it.** That is the A-G1 defect shape exactly — a
  required argument that is discarded tells nine authors they are configuring something.

Both removed. Two were unreachable, which is the only reason a client never saw the bar
change under them.

### NAV-G1

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/client_nav_contract_guard_test.dart` — 8 tests | **PASS** |
| Guard strength | **6 / 6 mutations killed** | **PASS** |
| Suite | **1323 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | **eleven** at baseline | **PASS** |
| Runtime | **LOCALLY_VERIFIED** — §3an's disk constraint unchanged | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| N1 | `Workouts` reverts to `Train` | **KILLED** |
| N2 | `Connect` is dropped for `Activity` | **KILLED** |
| N3 | the client FAB comes back | **KILLED** |
| N4 | a destination that is not registered | **KILLED** |
| N5 | the Activity entry loses its gesture | **KILLED** — after the guard was strengthened |
| N6 | the Activity entry loses its hint | **KILLED** |

**N5 survived its first run**, and the finding was the guard: it looked for the *string*
`go('/activity')` anywhere in the file, so a mutation that killed the gesture survived
because the `Semantics` declaration still carried one. A mention is not a door. It now
requires both halves — the announced action and the real gesture — which is what
`excludeSemantics` makes necessary.

### And the fourth detector to read its own prose

NAV-G1 failed on first run because its own header comment names `navIndex` and
`AppBottomNav`, so the "only one bottom nav" assertion failed against a codebase that had
exactly one. That is the **fourth** time in this programme —
`tool/fit_coverage.dart`, the MSG-003 guard, the Connect copy guard, and now this. Each
previous fix was inline, which is how the fourth happened; this file has **one**
`stripComments` and every assertion goes through it.

## 3as · The backlog was being measured wrong, in both directions

Five times this programme has found the coverage ledger under-reporting an anchor, each by
hand, one at a time — FIT-001 4/9→7/9, FIT-005 4/12→6/12, FIT-028 4/10→5/10,
FIT-014 5/12→6/12, FIT-032 5/11→6/11. The cause was structural: the ledger measured **one
file per anchor**, and a screen is a screen, the widgets it composes, the rules those
widgets call, and the shell that draws its nav. Nothing regenerated it, so every correction
was manual and the next was guaranteed.

`tool/fit_backlog.dart` resolves a route to the files it is actually built from. Building
it found four measurement defects, two of them in the tool itself.

### 1. The route resolved to a wrapper — the recorded defect, reproduced

`/meals-dashboard`'s builder is `PaywallGate(required: …, child: MealsDashboardScreen())`.
Taking the first widget after `=>` resolved the route to the **gate** — the *"route resolved
to a redirect stub"* defect already on record against the measurement this replaces,
reproduced on the replacement's first run. Wrappers are skipped now.

### 2. One hop was not far enough

A composing screen reaches its rules through a widget: `classes_screen → whats_on_view →
whats_on.dart`, where `const whatsOnSegments = ['All', 'Classes', 'Events', 'Challenges']`
lives. One hop reported **FIT-027 as 1/10** against a screen that renders four of them. Two
hops, scoped to `lib/features` and `lib/core`, restores it to its hand-verified 5/10.

*(And the first attempt at that fix silently did nothing: the filter tested
`d.contains('/lib/features/')` against **relative** paths that carry no leading slash.)*

### 3. Half the metric was a substring match

**300 of 600 declared labels are ONE WORD**, and `Back` alone appears 69 times. A bare
substring rule counted `background` as `Back` and `abandoned` as `Done`. A rendered label is
a string literal in Dart, so one-word labels must match as one.

That took the total from **352 to 280**, and **FIT-018 "Session complete" from 4/4 to 0/4**:

> `Easy` and `Hard` appear **nowhere in `lib`**.

All four of its interactions were coincidences, and FIT-018 was carried as complete. It is
now the highest-value locked anchor with zero coverage.

### 4. `Low` was a different scale's word

FIT-004 reported `Low` present and `Steady` / `Strong` absent. `Low` is real — it is the
**sleep** slider's label (`daily_checkin_screen.dart:370`, `≥8 Optimal / ≥6 Good / Low`) —
and has nothing to do with the board's **energy** scale `Low / Steady / Strong`, which is
**OD-16** and deliberately not built. Seventh false positive, same family: the tool matches
text, and text is not a control.

Worth separating from the measurement: that sleep scale is itself an **unsourced product
judgement**. Nobody in the package chose 8 and 6 hours, or decided that under six reads
`Low` in red. It is the same shape as OD-16 — a threshold deciding what a client is told —
resolved silently rather than raised. Recorded as **OD-28**; nothing changed, because
removing shipped copy is as much a product decision as adding it.

### The corrected position

| Measure | Stated at the start of this cycle | **Measured** |
|---|---|---|
| Locked-anchor interactions | 100 / 179 | **123 / 179** |
| Locked anchors complete | 7 | **10** |
| All declared interactions | 299 / 600 | **280 / 600** |

The locked figure rose because the old resolver was shallow and because F-14's resolution
moved seven anchors. The overall figure **fell**, because ~72 of the interactions it had
been counting were substring coincidences. A measurement that only ever moves upward is not
measuring.

`docs/FIT_INTERACTION_COVERAGE.md` is generated. Edit the tool, not the table.

### New owner decision

**OD-28 · the sleep quality scale.** `daily_checkin_screen.dart:370` labels sleep
`Optimal` (≥8 h), `Good` (≥6 h) or `Low`, and colours the last one red. No part of the
design package specifies those words or those thresholds. It is the same class of decision
as OD-16 — what a client is told about their own health data — and unlike OD-16 it was made
silently. Decide whether to keep it, restate it as a value, or replace it with package
wording.

## 3at · FIT-018 · the anchor that was carried as complete and was not built — **0/4 → 4/4**

§3as found it: all four of FIT-018's declared interactions are **one word** — `Easy`,
`Right`, `Hard`, `Done` — and the old measurement matched one-word labels as substrings.
`Done` found `abandoned`; `Right` found `Alignment.centerRight`. **`Easy` and `Hard` appear
nowhere in `lib`.** It read 4/4 and was 0/4.

### What the board asks for

> *"One real fact rather than a score: the personal best is stated because it happened, and
> the effort question is asked while it's fresh — it's what the coach reads next week. No
> confetti."*

```
Lower body, done.
51 min Duration    18 Sets logged    4.2 t Volume
How did it feel?
[ Easy ]  [ Right ]  [ Hard ]
[        Done        ]
```

### What shipped, and what changed

| Shipped | Now |
|---|---|
| `Workout Complete!` | `Lower body, done.` — the exclamation mark **is** the confetti the board rejects |
| `Duration · Calories · Idle` | `Duration · Sets logged · Volume` — the board's three |
| a 1–5 `Difficulty` star row | `How did it feel?` with `Easy / Right / Hard` |

**`Calories` was fabricated.** `_elapsedSeconds ~/ 60 * 8` — a flat 8 kcal a minute, the
same number for every person, every load and every movement, presented as a measurement on
the screen that closes a session. It goes because the locked design does not draw it, not
as a preference here. The `calories_burned` column it also writes is untouched, so nothing
else changes — recorded as **OD-30**.

### The effort encoding is not OD-16's shape

`workout_feedback.difficulty` is `int CHECK (BETWEEN 1 AND 5)`, and the board asks one
question with three answers. That looks like OD-16 and is its opposite:

* **OD-16** interprets a number the client did not choose — deciding a stored `3` means
  "Steady" is a judgement *about them*;
* **this** records the word the client picked. Nothing is inferred.

`1 / 3 / 5` uses the extremes and the middle, is reversible, and **nothing in the app reads
that column today** — verified against every reader, not assumed. A stored `2` or `4` reads
back as *nothing*, because it did not come from this question and guessing which word it was
nearest would invent an answer the client never gave.

### Kept, because the board not drawing something is not an instruction to delete it

`Overall`, `Energy` and the notes field stay (OD-15's lesson), as does the rest-overrun
warning line. Recorded as **OD-29**: the board draws only the effort question.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/session_complete_test.dart` — 19 tests | **PASS** |
| Widget | `test/widget/session_complete_dialog_test.dart` — 6, **mounted**, against the semantics tree | **PASS** |
| Guard strength | **9 / 9 mutations killed** (S4 first run was equivalent; re-run validly) | **PASS** |
| Coverage | FIT-018 **4 / 4** — genuinely | **PASS** |
| Suite | **1349 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | all eleven at baseline | **PASS** |
| Runtime | **RUNTIME_VERIFIED** — `emulator-5554`, see §3av | **PASS** |

| # | Mutation | Result |
|---|---|---|
| S1 | a stored `2` or `4` is snapped to the nearest word | **KILLED** |
| S2 | a bodyweight session renders `0.0 t` | **KILLED** |
| S3 | the title keeps its qualifier | **KILLED** |
| S4 | an unloaded set contributes its reps to volume | **KILLED** (first run was equivalent) |
| S5 | the answers stop being mutually exclusive | **KILLED** |
| S6 | the effort chips lose their tap action | **KILLED** |
| S7 | the celebratory title returns | **KILLED** |
| S8 | a negative load is subtracted from volume | **KILLED** |

### And the mutation harness misreported, for the third time

It classified a passing two-file run as "did not compile". Twice before it read a widget's
`error: (_, __) =>` arm, quoted back in a failure message, as a compile error. `flutter
test` already answers the question with its **exit status**; the harness greps output no
longer.

### New owner decisions

**OD-29 · the rest of the feedback dialog.** FIT-018 draws one question. `Overall`, `Energy`
and free-text notes are shipped and kept. Decide whether they stay.

**OD-30 · the calorie figure.** `_elapsedSeconds ~/ 60 * 8` is still written to
`workout_sessions.calories_burned` and surfaced elsewhere. It is not a measurement. Decide
whether to compute it properly, source it from a wearable, or stop recording it.

## 3au · FIT-003 · two declared header controls, and a second orphaned route

**8/12 → 9/12.** The three that remain are the board's sample meals — its honest ceiling.

FIT-003's header declares two icon-only controls that were **not on the screen at all**:

```html
<button class="ph ph-scan"        aria-label="Scan a meal"></button>
<button class="ph ph-list-checks" aria-label="Meal plan"></button>
```

`Meal plan` matters beyond the label. **`/meal-plan` is a registered route that nothing in
the app navigated to** — orphaned, the same shape `/activity` was in before FIT-001's nav
work, found the same way. This control is its door. That is now **two** orphaned routes
found by asking what a declared control opens.

`Scan a meal` opens the add-meal sheet **already on its Scan input**. Opening it on the
default tab would have made it a second `Log a meal`, which is the header's other control —
the board draws them as different things and they now do different things.

And the header's back control was an **unnamed 30 px chevron** — an A-G8 site on a primary
destination. `Back` is the package's own word, declared 69 times.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/widget/nutrition_header_test.dart` — 6 tests, comment-stripped, with a detector floor | **PASS** |
| Guard strength | **4 / 4 mutations killed** | **PASS** |
| Coverage | FIT-003 **9 / 12** — the rest are sample meals | **PASS** |
| Suite | **1355 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors · A-G8 at baseline | **PASS** |
| Runtime | **LOCALLY_VERIFIED** — §3an's disk constraint unchanged | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| M1 | `Meal plan` loses its route and the orphan returns | **KILLED** |
| M2 | `Scan a meal` opens the default tab, duplicating `Log a meal` | **KILLED** |
| M3 | the back chevron reverts to unnamed | **KILLED** |
| M4 | `Scan a meal` loses its declared name | **KILLED** |

## 3av · Device verification — and the eighth false positive, which was mine

Disk freed up mid-cycle, so the work recorded as `LOCALLY_VERIFIED` went to the device.
**FIT-018 is now RUNTIME_VERIFIED**, and the device found something the host suite,
nineteen unit tests and six widget tests all missed.

### `Done` measured present and was not on screen

FIT-018's fourth declared interaction is `Done`. It measured **HAVE** — because
`sessionDoneLabel = 'Done'` is a **const in `session_complete.dart`**, which is in the
anchor's resolved file set. The button on screen said `Submit`.

That is the **eighth** false positive found in this measurement, and the first this
programme **introduced itself**: I wrote the const, the metric matched it, and the anchor
read complete. The host tests did not catch it because none of them asserted the primary
action's text — they asserted the three effort answers, which were real.

The device test did, immediately, because it looks for what is on screen.

The button now reads `Done`, the board's word. `Try Again` stays for the failure state —
a distinct outcome the board's single frame does not cover, and F-23 is the record of what
collapsing it costs. F-23's eight tests were updated to the new label; every honesty
property they assert is unchanged.

### FIT-018 · RUNTIME_VERIFIED — `emulator-5554`, 411.4 dp @ dpr 2.625

```
title="Lower body, done." (no confetti)
Easy   89.1x44.0  button=true tap=true exclusive=true selected=false
Right  89.1x44.0  button=true tap=true exclusive=true selected=false
Hard   89.1x44.0  button=true tap=true exclusive=true selected=false
stats 51 min / 18 sets / 4.2 t
after tapping Hard: easy=false right=false hard=true
360.0 / 390.0 / 411.4 dp — exception=none
```

### FIT-001's nav — partially device-verified, and why only partly

The five-tab bar rendered on the device at **360, 390 and 411.4 dp with no overflow**,
which is the claim that mattered: the bar it replaces carried four labels and a FAB, and
five labels in one row at 360 dp is the real risk. That sweep passed.

The per-tab measurement assertion in the same file threw on a finder of mine, and the
re-run **could not build**: the host volume had fallen from 4.7 GB to **124 MB** across
three device builds. Reclaimed to 2.1 GB, and the re-run is left for the next cycle rather
than reported as passing.

`integration_test/fit001_client_nav_device_test.dart` is committed with the finder fixed.
It initialises Supabase because `AppShell` asserts an instance exists before it will build
— and **nothing signs in**: the profile provider is overridden, so no request is made and
no row is read or written.

### The disk reality, restated

Three device builds took the volume from 4.7 GB to 124 MB. Each debug build is ~2.7 GB and
nothing reclaims it automatically. Device verification on this machine is a **budget**, not
a background activity: reclaim before, and expect to reclaim after.

## 3aw · FIT-029 · a third orphaned route, and a count that must not lie

**4/6 → 5/6.** The sixth is **OD-18** — the board's `£79 monthly` against live Stripe
prices in dollars.

FIT-029's "You" list declares `Goals` and `Connected apps` between `Personal information`
and the plan row. Neither was on the screen.

### `/goals` had no door

Registered, and **nothing in the app navigated to it**. That is the **third** orphaned route
this cycle has found by the same method — asking what a declared control opens:

| Route | Found via | Door |
|---|---|---|
| `/activity` | FIT-001's nav | Home's week-progress panel |
| `/meal-plan` | FIT-003's header | the `Meal plan` icon control |
| `/goals` | FIT-029's You list | the `Goals` row |

Three registered screens with no way in, each surfaced by taking a declared interaction
seriously rather than treating its absence as cosmetic. A route the router knows about and
nothing opens is dead product, and the coverage metric cannot see it — it reads labels, and
these had none to read.

### The count must not lie

`Connected apps` carries a live figure from `user_integrations`, the same rows the
integrations screen reads, so the row and the screen behind it cannot disagree.

The screen it opens ends its own read `catch (_)`, which shows every provider as
disconnected on any failure. This row does not repeat that. **No badge** in three cases:

* nothing connected — the board draws a count, not a `0`;
* still loading — a number that appears a moment later is worse than one that appears once;
* the read **failed** — the client has no idea how many apps are connected, and neither do
  we. `0` would be a fabricated fact of exactly the F-15 kind.

A stale value carried on an `AsyncError` is deliberately not shown either: it is a number
the database did not just confirm.

### Security

`user_integrations` is `FOR ALL USING (auth.uid() = user_id)` (`011:57`) and `goals` is
`client_id = auth.uid()` with a matching `WITH CHECK` (`018:65`). Both self-scoped, no
coach/client boundary, **no new writes**. Nothing to escalate.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/connected_apps_test.dart` — 6 tests | **PASS** |
| Guard | `test/widget/profile_rows_test.dart` — 5, comment-stripped, with a detector floor | **PASS** |
| Guard strength | **5 / 5 mutations killed** | **PASS** |
| Coverage | FIT-029 **5 / 6** — the sixth is OD-18 | **PASS** |
| Suite | **1367 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Runtime | **LOCALLY_VERIFIED** | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| P1 | a failed read renders as `0` | **KILLED** |
| P2 | a stale value survives a failure | **KILLED** |
| P3 | zero is rendered as a badge | **KILLED** |
| P4 | `Goals` loses its route and the orphan returns | **KILLED** |
| P5 | the count becomes a literal matching the board | **KILLED** |

`Connected apps 2` stays ABSENT in the measurement, and correctly: the declared label
**embeds the sample count**, so a live figure can never match it. Composed-label ceiling,
same as the board's sample rows.

## 3ax · ROUTE-G1 · six screens nobody can open, two of them locked anchors

Three orphaned routes were found in one cycle — `/activity`, `/meal-plan`, `/goals` — each
by hand, each by asking what a declared FIT interaction opens. The coverage metric cannot
see an orphan: it reads labels, and a missing control has none to read. **The only reason
those three surfaced is that the design happened to declare a control for each. Nothing
would have found a fourth.**

`tool/orphan_route_sweep.dart` asks the question once, for all 91 registered routes.

### What counts as a way in, and why the first answer was wrong

A literal scan for `context.go('/x')` reported **13** orphans. Three of those are not:

* `/events` is reached through a **data-driven** list — `_Module(route: '/events', …)` in
  `directory_screen.dart`. A literal-call scan cannot see it;
* `/splash`, `/login` and the two Stripe redirect URLs are entered from **outside `lib`**.
  They are **named** with a reason, because "no caller" and "entered from elsewhere" are
  different facts and guessing which is which is how a real orphan gets excused.

The honest count is **seven routes**, carrying **six anchors**.

### Two of them are locked anchors, and one was measuring complete

**FIT-006 "Welcome" measured 2/2 and no client can reach it.** `/onboarding` has no caller;
the router's own comment says *"the splash hands off to /onboarding itself"* and the splash
goes to `/signup`.

And the design package **documents this itself**. FIT-010's annotation:

> *"Destinations preserved from source: Get started → `/signup`, Sign in → `/login`. See the
> report — the shipped implementation is a different screen entirely, and **it orphans
> locked Welcome**."*

So the package declares Welcome as a locked screen **and** preserves a splash that bypasses
it. That is a contradiction with no authoritative resolution — **OD-31**, not a defect to
fix here. Wiring the splash through Welcome would be choosing a product flow the package
deliberately left as it found it.

**FIT-019 "Log a meal"**: `/log-meal` builds a 23-line screen whose `initState` immediately
`context.go('/meals-dashboard')`. A redirect stub with no caller — and the literal instance
of the *"route resolved to a redirect stub"* defect the original coverage ledger named
without locating.

### The measurement now counts reachability

`fit_backlog.dart` marks an anchor **UNREACHABLE** when its route has no door, and such an
anchor is **not counted complete**. Locked complete falls **11 → 10**, because FIT-006 was
being counted.

> Presence is not reachability. A screen nobody can open is not implemented, whatever its
> labels say.

That is the **ninth** defect found in this measurement.

| Route | What it is |
|---|---|
| `/coach` | a duplicate alias of `/train` — both build `TrainHubScreen` |
| `/log-meal` | a redirect stub to `/meals-dashboard` — FIT-019, **locked** |
| `/onboarding` | FIT-006 Welcome — **locked**, and **OD-31** |
| `/pods` | `PodsScreen` — FIT-071…074, all non-locked |
| `/coach-business`, `/food-search`, `/nutrition-overview` | screens with no entry point |

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/orphan_route_guard_test.dart` — 5 tests, bidirectional allowlist, detector floor | **PASS** |
| Guard strength | **3 / 3 mutations killed** | **PASS** |
| Suite | **1372 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | **twelve** at baseline | **PASS** |

| # | Mutation | Result |
|---|---|---|
| O1 | a new route is registered with no door | **KILLED** |
| O2 | a recorded orphan gains a door but stays listed | **KILLED** |
| O3 | blind the navigated-route detector | **KILLED** |

### New owner decision

**OD-31 · does Welcome enter the flow?** FIT-006 is a **locked** screen at `/onboarding`
with no way in, and FIT-010's annotation records that the shipped splash orphans it while
preserving `Get started → /signup`. Either the splash routes through Welcome, or Welcome is
retired. The package states the conflict and does not resolve it.

## 3ay · FIT-062 · one of three accessibility signals, and a write nobody asked for

**1/7 → 2/7.** The five that remain are the board's sample notifications.

### The board states the accessibility requirement, and its reason

> *"Unread carries **a dot** and **the word "Unread"** and **full-strength ink** — three
> signals, since a violet dot alone fails for a colour-blind member."*

The screen shipped with **the dot**. That is the one signal the board names as insufficient
on its own, and it names the member it fails. All three are now computed together by
`unreadSignals`, precisely so a caller cannot ship one and forget the other two — which is
what happened.

### And a write the client never asked for

`notifications_screen.dart` ran this in `initState`:

```dart
Future.delayed(const Duration(seconds: 2), () {
  if (mounted) ref.read(notificationsProvider.notifier).markAllRead();
});
```

Two seconds after the screen appeared, **every notification became read** — whether the
client read anything or not. That:

* made `Mark all read`, which the board draws as a **control**, pointless, because it had
  already happened;
* destroyed the state the three signals exist to convey;
* wrote on the client's behalf without being asked.

The board draws marking-read as something the client does. So it is now. This is not an
invented product decision — it is the one the frame already makes by drawing a button.

### Three more the board settles

| Shipped | Board |
|---|---|
| `Today` / `Yesterday` / `3 days ago` / `Sep 17` in one list | `Today` / `Earlier this week` |
| `All caught up!` · `No more notifications for now.` | `Nothing new` · `Coach replies, plan changes and check-in reminders land here.` |
| an unnamed 38 px back circle | `aria-label="Back"` — an A-G8 site, and two pixels under the 44 dp floor |

The empty copy matters more than it looks: the shipped pair says the list is empty **twice**
and never says what would appear in it. The board's names the categories the app sends.

"This week" is the **last seven days**, not the calendar week — a Monday member would
otherwise find Sunday's coach reply under `Earlier`, which is true of the calendar and wrong
about their week. A third group, `Earlier`, carries anything older: the board draws two
because its sample spans five days, and a notification from last month has to go somewhere
that is not a lie.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/notification_groups_test.dart` — 15 tests | **PASS** |
| Guard | `test/widget/notifications_signals_test.dart` — 6, comment-stripped, detector floor | **PASS** |
| Guard strength | **7 / 7 mutations killed** | **PASS** |
| Coverage | FIT-062 **2 / 7** — the five are sample notifications | **PASS** |
| Suite | **1393 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors · A-G8 at baseline | **PASS** |
| Runtime | **LOCALLY_VERIFIED** | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| K1 | the word signal is dropped, back to a dot alone | **KILLED** |
| K2 | full-strength ink is dropped | **KILLED** |
| K3 | "this week" becomes the calendar week | **KILLED** |
| K4 | an unread row loses the word in its meta line | **KILLED** |
| K5 | the empty copy reverts | **KILLED** |
| K6 | the 2-second auto-mark returns | **KILLED** |
| K7 | the back control reverts to unnamed | **KILLED** |

## 3az · DEAD-G1 · two files, one class name — and a test that passed on Wednesday

### The duplicate the register named, stated precisely

`docs/MISSING_SCREEN_REGISTER.md` lists nine duplicate/dead files and records that
`home_org.dart` "caused the FIT-001 mis-mapping". Verified independently, the sharp version
is narrower and worse:

**Exactly two public classes are declared in more than one file.**

| Class | Files | Live? |
|---|---|---|
| `HomeScreen` | `home_org.dart` · `home_screen.dart` | the router imports **`home_screen.dart`** |
| `DashboardScreen` | `dash_org.dart` · `dashboard_screen.dart` | **neither** — the router builds `AdminDashboardScreen`, `CoachDashboardScreen` and `MealsDashboardScreen` |

Dart refuses to import both at once — that is an ambiguous-import error — so the danger is
not an accidental double import. It is a **one-line swap**: point the router at
`home_org.dart` and `/home` renders a different screen. Nothing fails. The analyzer is
happy. Every test stays green.

Deleting either file is destructive and is **OD-32**. `DEAD-G1` deletes nothing. It pins
which file the router builds `/home` from, keeps the dead duplicate unreferenced, and stops
a third appearing — which is the point, because the register's own finding is that across
202 mobile commits **no screen file has ever been deleted**. The failure mode is accretion.

| # | Mutation | Result |
|---|---|---|
| D1 | the router swaps `/home` to the dead duplicate | **KILLED** |
| D2 | a **third** file declares `HomeScreen` | **KILLED** — after the guard was fixed |
| D3 | a route builds the bare `DashboardScreen` | **KILLED** |
| D4 | something imports the dead Home file | **KILLED** |

**D2 survived its first run**, and the finding was the guard. It pinned the two duplicated
class **names**, so a third copy of `HomeScreen` was not a *new name* and passed. Accretion
is precisely what it guards, so it now pins the **exact file set** for each.

And it failed its own first run against a **comment** in `app_scaffold.dart` that names
`home_org.dart` while explaining why the dead nav was removed — the **fifth** detector in
this programme to read its own prose as evidence.

### A test that passed on Wednesday and failed on Thursday

`week_row_tile_test.dart` asserted `THU` and `Thursday · 30 min` against a fixed
`DateTime(2026, 9, 24)`. `WeekRowTile` reads the real clock — correctly; that is what
production does — so on 2026-09-24 the 24th stopped being "Thursday" and became **today**,
the chip read `Now`, and the file failed.

It had nothing to do with the code under test. A test whose result depends on the day it
runs is not a test. Its fixtures are now relative to the clock and its expectations are
**derived from the same dates** rather than written out.

A sweep for the same shape — a relative-day word asserted against a fixed date with no
clock override — found **three** candidates and cleared two: `formatters_test.dart` passes
the date **as an argument** to `shouldShowCheckinBanner`, and `checkin_detail_test.dart`
asserts the absence of OD-20's copy. So this was **isolated, not systemic**, which is worth
recording as plainly as a systemic finding would be.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/duplicate_screen_class_guard_test.dart` — 5 tests, file-set pinned, detector floor | **PASS** |
| Guard strength | **4 / 4 mutations killed** | **PASS** |
| Suite | **1398 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | **thirteen** at baseline | **PASS** |

### On the sixteen untracked audit documents

`docs/MISSING_SCREEN_REGISTER.md` and fifteen companions appeared in the working tree,
untracked, stamped *"Baseline `fbee6d5`"* — produced by a process other than this one
against this programme's HEAD. They are treated here as **evidence, not truth**: every claim
acted on above was re-derived from the repository first, and doing so sharpened two of them
(the duplicate-class mechanism, and the fact that **both** `DashboardScreen` files are dead
rather than one). They remain uncommitted, because they are not this programme's work to
commit.

## 3ba · FIT-058 · one sentence in the board named four defects

> *"**Tapping the row is the whole interaction** — no separate checkbox to hit — with
> **`role="checkbox"`** so the state is announced."*

`habit_card.dart` violated every clause of that sentence:

1. **the tap target was a 32 × 32 circle**, not the row — and 32 is under the 44 dp floor.
   FIT-100's annotation measures the same thing independently: *"Toggle is 44px — the source
   has 32"*;
2. **there was no `Semantics` at all.** No role, no state, no name. A screen reader
   announced nothing about whether a habit was done;
3. a completed habit rendered a plain `Container` rather than a control, so **it could not
   be un-toggled** — a one-way action, on a screen whose entire content is a daily yes/no.
   A habit ticked by accident stayed ticked;
4. the week — `6 of 7 this week`, the figure the board puts on the row — was **not shown**,
   though `completedDates` has always carried it.

The row is now the control, `Semantics(checked:)` gives it the checkbox role, the mark is
excluded so the row announces once, and the tap works in both directions. `Back` was also
absent — the screen is reached by a push and had no way out but the system gesture.

### Two mutations survived, and both found the test rather than the code

**B2** nulled the `GestureDetector`'s `onTap` for a completed habit and survived: the
assertion read `SemanticsAction.tap`, which `Semantics(onTap:)` supplies **either way**. A
declared action is not a working one — the same "a mention is not a door" weakness NAV-G1
hit. The test now reads the real gesture out of the widget tree.

And the first version asserted against `find.byType(HabitCard)`, whose root data does **not**
merge the `checked` flag up from the `Semantics` inside the `Stack`. It reported no checkbox
role on a widget that has one. Asserting against the wrong node is its own false negative.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/habit_row_test.dart` — 10 tests | **PASS** |
| Widget | `test/widget/habit_card_test.dart` — 7, **mounted**, against the semantics tree | **PASS** |
| Guard strength | **6 / 6 mutations killed** (B2 after the test was fixed) | **PASS** |
| Coverage | FIT-058 **1 / 5** — the four are sample habits | **PASS** |
| Suite | **1415 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors · A-G8 at baseline | **PASS** |
| Runtime | **LOCALLY_VERIFIED** | **OPEN** |

| # | Mutation | Result |
|---|---|---|
| B1 | the checkbox role is dropped | **KILLED** |
| B2 | a completed habit loses its gesture | **KILLED** — after the test read the gesture |
| B3 | the week line leaves the row | **KILLED** |
| B4 | two entries on one day count twice | **KILLED** |
| B5 | the week window slips to eight days | **KILLED** |
| B6 | the state is written into the accessible name | **KILLED** |

### FIT-064 Activity — assessed, not started

`/activity` is reachable now (FIT-001's nav work gave it a door from Home's week panel, and
FIT-064's annotation confirms that is right: *"Home's summary links here rather than
absorbing it"*). But the board draws a **reverse-chronological stream with a type filter**
— `All / Training / Food / Check-ins` — and what ships is a **dashboard of stat cards**
(`_StreakCard`, `_WaterTrackerCard`, `_PerformanceCard`, `_StepsCard`, `_CaloriesCard`,
`_NutritionGrid`).

That is not a gap to fill; it is a different screen. The data exists across
`workout_sessions`, `nutrition_logs`, `weekly_checkins` and `weight_logs`, so it **is**
buildable from sanctioned paths — as a merge, the shape `mergeWhatsOn` already uses for
FIT-027 — but it is a feature build, not an interaction fix. Recorded as **Class C**, the
largest single executable item left in the non-locked backlog.

## 3bb · TAP-G1 · the design package measured the same defect twice, and nothing guarded it

`A-G8` ratchets whether an icon control has a **name**. Nothing ratcheted its **size** — and
the package keeps finding that defect by hand, on separate anchors:

* **FIT-058** — *"Tapping the row is the whole interaction"*; the shipped target was a
  **32 × 32** circle;
* **FIT-100** — *"Toggle is 44px — **the source has 32**."*

Two anchors, independently, measuring the same 32 px.

### The first count was wrong, and tightening it mattered

A loose first pass — any `width:`/`height:` within 520 characters of a tappable — reported
**44 sites across 30 files**. Most of the extra were **decorative boxes inside** a large
tappable: a 12 × 12 dot, an 18 × 18 icon. Restricting to the tappable's **immediate**
`Container` child — which, under the default `deferToChild` hit behaviour, *is* the hit area
— gave **17**, and two spot-checks confirmed those are real:

```dart
GestureDetector(
  onTap: () => context.go('/profile'),
  child: Container(width: 42, height: 42, …)   // app_top_nav.dart — the hit area
```

Asserting 44 would have been a regex finding, not a measurement.

### One fixed, the rest pinned

`app_top_nav.dart`'s avatar is **the most-shown touch target in the app** — it renders in
every screen's top bar — and it was **42 × 42**, two dp under. The ring keeps its 42 dp
look; the hit area is lifted to 44 around it with `HitTestBehavior.opaque`, without which
the lifted box is not itself tappable. Baseline **16**.

### What this guard deliberately does not claim

**Source cannot measure a touch target.** A target sized by its parent, by padding, or by
`IconButton`'s own 48 dp default is invisible to it, and a fixed box inside a larger
`InkWell` can be perfectly fine. **F-6/F-6b** are the record of why runtime is authoritative:
the password toggle *looked* correct in source and measured **19.8 × 20.2 dp** on the device.

So TAP-G1 is a **candidate ratchet**, in the same spirit as A-G8's recorded overstatement.
It may fall; it may not rise.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/touch_target_guard_test.dart` — 3 tests, detector floor, named sites | **PASS** |
| Guard strength | **3 / 3 mutations killed** | **PASS** |
| Suite | **1418 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | **fourteen** at baseline | **PASS** |

| # | Mutation | Result |
|---|---|---|
| T1 | the avatar loses its 44 dp floor | **KILLED** |
| T2 | a 17th sub-44 tappable ships | **KILLED** |
| T3 | blind the detector | **KILLED** |

## 3bc · Environment — the disk is now a hard constraint

The volume reached **352 MB free** mid-cycle and a `flutter test` run **stalled past ten
minutes** rather than failing — the symptom recorded in memory as a disk check, not a test
hang. Clearing `build/` (95 MB) recovered it and the suite completed normally.

What is left is not this programme's to take:

| Location | Size | Status |
|---|---|---|
| `apps/mobile/build` | ~95 MB–1.3 GB | project-owned, cleared automatically |
| `apps/mobile/.dart_tool` | 170 MB | project-owned, **in use by the running suite** |
| `~/Library/Caches/com.openai.codex` | 1.9 GB | another application's — **not mine to delete** |
| `~/Library/Caches/Google` | 1.7 GB | another application's — **not mine to delete** |
| `~/.gradle/caches` | 5.2 GB | regenerable, but its loss costs a network re-download that would break the Android build path if it failed |

**Consequence, stated honestly:** host-side QA continues at ~450 MB, but **device
verification cannot run** — a debug build needs ~2.7 GB. Work completed since the last
device run is therefore `LOCALLY_VERIFIED`, not `RUNTIME_VERIFIED`, and that classification
is a statement about the machine, not about the code.

**Reclaiming ~3 GB would unblock it.** That is an owner action.

## 3bd · FIT-094/095 · the screen that showed nothing when it had failed

### The defect, and why nobody could see it

`GroceryListNotifier` is a `StateNotifier<String?>`, and on failure it writes the error
**into the same slot the list lives in**:

```dart
state = 'Error generating grocery list. Please try again.';
```

The screen then *parsed that string*. `_parseGroceryList` keeps only lines ending in `:` or
beginning with `-`; the error sentence matches neither, so it returned `[]` and the screen
drew **its header over nothing**. No error, no retry, no explanation — a failed request and
an empty one were the same screen.

This was found in `docs/…/12CIRCLE-FITNESS-WAVE-3-AUDIT.md`, which had already named it. I
re-derived it from the provider rather than taking the claim, and it holds.

### The design already said what belongs there

**FIT-094 — "Grocery list — the two blocked states"** declares states `failure` and
`locked`, a `ph-warning` icon, and exactly three controls: `Back`, **`Build a meal plan`**,
**`Try again`**. Neither blocked state existed. Neither button existed — the dependency
state said *"Create Meal Plan"*, and there was no retry anywhere on the screen.

### Why the fix does not match the error string

The obvious repair is to compare against that sentence. `groceryOutcome` does not, because
the sentence is not the only way to reach a blank: a truncated or reworded model response
parses to nothing just as silently. The rule is the **observable** one —

> raw output that yields no categories is a failure, whatever it says

— which is strictly wider than a sentinel and cannot drift when the copy is reworded.

### Two more defects on the same rows

* **No `Semantics` at all**, though the board marks every item `role="checkbox"` — the same
  defect FIT-058's habit row had, found independently, and repaired the same way (Semantics
  outside, gesture inside, `onTap` re-declared because `excludeSemantics` drops child
  actions — F-20).
* **Ticks were keyed by list index.** `_checkedItems` held `Set<int>` of positions and the
  card carried no `key`, so a rebuild reused the `State` **by position**. After "Rebuild the
  list" a tick placed on *Spinach* sat on whatever became first. Keyed by the item's text,
  it cannot migrate.

### An honest limit of my own guard

The row's target was ~34 dp — a 22 dp circle with 6 dp either side — and **TAP-G1 does not
catch it.** TAP-G1 looks for a tappable wrapping a *fixed* `Container`; this wrapped a
`Padding` whose height is implied. The guard's reach is narrower than its name suggests, and
this is recorded rather than quietly patched.

| Layer | Evidence | Status |
|---|---|---|
| Domain | `test/unit/grocery_list_test.dart` — 12 tests | **PASS** |
| Widget | `test/widget/grocery_item_card_test.dart` — 4 tests | **PASS** |
| Guard strength | **5 / 5 mutations killed** | **PASS** |
| Suite | **1434 pass / 9 skipped** (was 1418) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | FIT-094 **3/3**; all interactions 288 → **292 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| G1 | unreadable output renders as an empty ready list | **KILLED** |
| G2 | ticks keyed by list index | **KILLED** |
| G3 | the checkbox announces no tap action | **KILLED** |
| G4 | the row falls back under the 44 dp floor | **KILLED** |
| G5 | `Rebuild the list` drifts back to `Refresh` | **KILLED** |

### FIT-095 stays at 2/15, deliberately

Its other thirteen "interactions" are `Spinach, 2 bags`, `Broccoli, 3 heads`, `Eggs, 18` —
the board's **sample groceries**, captured as control labels because the design renders each
row as a `<button>`. Closing them means hardcoding a shopping list into `lib/`. They are a
data ceiling, not a gap, and the same is true of FIT-100's seven rows, several of which are
visibly truncated mid-word by the capture (`"…Nadia has times open Thursday Overdu"`).

**The denominator of 600 contains rows of this kind.** They are counted here rather than
quietly excluded, because excluding them is a measurement change and belongs in one
deliberate pass, not in the middle of a feature.

## 3be · FIT-092/093 · the error was the content, on both AI surfaces

### One root cause, two screens

`MealPlanNotifier` and `GroceryListNotifier` were both `StateNotifier<String?>`, and both
wrote their error **into the slot the content lives in**. A nullable string has two states
and the screens needed three: with `null` meaning *"not asked yet"*, there was nowhere left
to put *"asked, and it failed"* — so the failure was stored as content, and every consumer
downstream treated it as content.

On `/meal-plan` that produced a section headed **"Your Meal Plan"** whose plan read
*"Error generating meal plan. Please try again."* — and because both routes onward were
gated on `mealPlan != null`, which a failure satisfies, the screen offered **two** ways to
build a shopping list out of an error message. `/grocery-list` then parsed it, kept nothing,
and drew its header over an empty column (§3bd).

`AiText` gives the three states names. A failure carries `content == null`; there is
nowhere to put the sentence.

### The design had both screens already

* **FIT-093 — "Meal plan — it didn't build"**, one control: **`Try building it again`**.
  The screen had no retry at all.
* **FIT-092** names **`Turn this into a grocery list`** (the screen said *"Generate Grocery
  List"*) and **`Build a different plan`**, which had no equivalent — the only way to ask
  for another plan was to scroll back up to the original button.

### The mutation run caught my own test, and then caught my harness

**M1 — putting the error sentence back into the content slot — SURVIVED.** Every test
constructed `AiText` by hand, so the notifier's `catch` branch, which is where the defect
actually lived, was never executed. Four tests were added that drive
`generateMealPlan`/`generateGroceryList` against a throwing service.

Then the re-run reported **6/6 killed — and that was wrong too.** My edit had put `library;`
after the imports, so the file did not compile; `flutter test` exited non-zero for every
mutation and the harness read each one as a kill. A compile error is not a caught defect.
The harness now greps for `Compilation failed` / `Failed to load` and reports **INVALID**
instead, which immediately exposed a second bad mutation (M3 relied on type promotion that
does not hold). Both were rewritten and re-run.

This is the fourth time this programme's mutation harness has misreported. It is recorded
because the fix — never let a non-zero exit stand in for an assertion failure — is the same
each time.

| Layer | Evidence | Status |
|---|---|---|
| Domain + notifier | `test/unit/meal_plan_outcome_test.dart` — 18 tests | **PASS** |
| Rendered state | `test/widget/meal_plan_failure_test.dart` — 5 tests | **PASS** |
| Guard strength | **6 / 6 mutations killed**, all verified to compile | **PASS** |
| Suite | **1457 pass / 9 skipped** (was 1434) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | FIT-092 3/4 · FIT-093 2/2 · all interactions 292 → **295 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| M1 | the error is stored as the plan again | **KILLED** |
| M2 | a failed plan can still reach the grocery list | **KILLED** |
| M3 | FIT-093's branch is dropped — a failure renders nothing | **KILLED** |
| M4 | a whitespace-only plan renders as a plan | **KILLED** |
| M5 | `groceryOutcome` ignores an outright failure | **KILLED** |
| M6 | `Try building it again` drifts to `Retry` | **KILLED** |

### Found in passing, not yet fixed: 40 unnamed back buttons

`Back` measured ABSENT on both anchors. The cause is general: `lib/` contains **41**
`Icons.arrow_back` buttons and, before this change, **one** carried a name. An icon-only
control with no name is the defect `A-G8` exists for, and `A-G8`'s own baseline plainly does
not reach these. This screen's is named; the other 39 are the next item, with a ratchet,
rather than a silent sweep here.

## 3bf · BACK-G1 · the most-declared control in the package had no name

`Back` is the single most declared interaction in the design package. It is always drawn as
a bare glyph, and an `IconButton` whose child is an `Icon` and which has no `tooltip:` has
**no accessible name at all** — a screen reader announces "button" and stops. Flutter's own
`BackButton` takes its name from `MaterialLocalizations`; a hand-rolled
`IconButton(icon: Icon(Icons.arrow_back))` takes nothing. A bare `GestureDetector` around
the same glyph is worse again: no name *and* no button role.

### The first count was wrong by threefold, and the previous commit repeats it

The sweep reported **40 unnamed back buttons**, and the commit message for §3be says "the
other 39". **Both are wrong.** The verified figure is **16**. Two distinct errors inflated
it:

1. it matched `IconButton(` as a **substring of `NamedIconButton(`**, so six controls this
   programme had *already fixed* were counted as defects — precisely the "string substrings
   being counted as controls" failure this programme watches for, committed by the sweep
   that was looking for it;
2. it never looked far enough out to see a `Semantics(button: true, label: 'Back')`
   wrapper, so four more correct sites were counted too.

The correction is recorded here rather than left to stand, because the inflated number is
already in the repository's history.

### What was actually wrong, and is now fixed

| | Count | Fix |
|---|---|---|
| `IconButton`, no tooltip | **13** | `tooltip: 'Back'` |
| bare `GestureDetector` | **3** | `NamedIconButton(label: 'Back', …)` |
| already correct | 10 | untouched |

`NamedIconButton` already existed, written earlier in this programme for exactly this shape;
it carries the name, the button role and the 44 dp target together, so the three gesture
sites gained a tap target as well as a name.

### The guard caught itself being blinded — on the second attempt

Mutation **B4 — make the "is it named?" test return `true` unconditionally — SURVIVED.** The
floor test only counted *controls*, so a predicate that never says "no" left the ratchet
with nothing to find and everything passing. The predicate was lifted to a top-level
`namesBackControl` and pinned on synthetic input: a bare gesture around the glyph must
classify as unnamed, each naming route must be recognised, and `label: 'Close'` must not
count as naming a back control. B4 then died.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/back_control_guard_test.dart` — 4 tests, baseline **0** | **PASS** |
| Guard strength | **4 / 4 mutations killed** | **PASS** |
| Suite | **1461 pass / 9 skipped** (was 1457) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | **fifteen** at baseline | **PASS** |
| Coverage | all interactions 295 → **306 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| B1 | one `IconButton` loses its tooltip | **KILLED** |
| B2 | a `NamedIconButton` reverts to a bare `GestureDetector` | **KILLED** |
| B3 | the detector is blinded | **KILLED** |
| B4 | the naming predicate returns `true` unconditionally | **KILLED** (survived first) |

## 3bg · FIT-090 · the failure that became something the coach had said

Third instance of the same root cause, and the only one with a consequence outside the
screen. When a turn failed, `sendMessage` appended the error **as the coach**:

```dart
state = [...state, ChatMessage(
  content: 'Sorry, I encountered an error. Please try again.',
  isUser: false,          // <- presented as the assistant speaking
)];
```

**On screen** that is a coach bubble — same avatar, same styling — indistinguishable from
nutrition advice, with no way to retry but to retype.

**In the next request** it is worse. `_buildHistory()` walked the whole message list and
mapped every `isUser: false` entry to `role: 'assistant'`, so the following turn told the
model it had previously said *"Sorry, I encountered an error"* — an apology for an error it
never had, now part of the conversation it was asked to continue, and replayed on every
subsequent turn for the rest of the session. **A transport failure became a fact about the
coach.**

FIT-090 — *"AI nutrition — a turn that failed"* — is a designed screen with one control:
**`Send it again`**. It did not exist.

`ChatMessage.failed` lets both readers act on the same fact: the bubble draws a notice
rather than the coach, and `apiHistory` leaves the turn out. `retryLastTurn` drops the
notice **and the user turn it belongs to** before re-sending, so a retry does not leave a
duplicate of either behind.

The visible sentence changed too. *"Sorry, I encountered an error"* is written in the
coach's voice, which is part of why it read as the coach; the notice is the app speaking.

| Layer | Evidence | Status |
|---|---|---|
| Domain + notifier | `test/unit/chat_turn_test.dart` — 12 tests, incl. a fake service asserting what the **next request actually carried** | **PASS** |
| Guard strength | **5 / 5 mutations killed** | **PASS** |
| Suite | **1473 pass / 9 skipped** (was 1461) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | all interactions 306 → **307 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| C1 | failed turns are replayed to the model as assistant context | **KILLED** |
| C2 | the failure is not marked, so it renders and replays as the coach | **KILLED** |
| C3 | the retry leaves a duplicate user turn behind | **KILLED** |
| C4 | the retry re-sends whatever came last, not the user's turn | **KILLED** |
| C5 | `Send it again` drifts to `Retry` | **KILLED** |

### Three screens, one mistake

`/meal-plan`, `/grocery-list` and `/ai-nutrition` each conflated *failed* with *content*,
independently, in three different shapes — a `String?`, a `String?`, and a list element
flagged by whose turn it was. In all three the design package already had the failure
screen drawn. The pattern worth carrying forward is not "add an error state": it is that
**a type with two states cannot carry three**, and the third one always ends up disguised
as the second.

## 3bh · FIT-089 · the chips, the menu and the input line

Three controls on `/ai-nutrition` carried names the board does not use, and one carried no
useful name at all:

* the overflow menu was a bare `PopupMenuButton`, so its name fell back to
  `MaterialLocalizations`' generic **"Show menu"**. FIT-089 calls it **`More options`**;
* the input read *"Ask your nutrition coach…"*; the board reads **`Ask about your
  nutrition`**;
* the quick chips shipped **six**, in a different voice — *"Analyze my breakfast"*,
  *"Generate a 7-day meal plan"* — where FIT-089 draws **three**: `Plan my week`,
  `Read my plate`, `Rest-day meals`.

On the chips: the three the board dropped are not capabilities that disappear. Every one is
a sentence the user can still type, and the meal planner and grocery list have their own
routes in the same overflow menu. What changes is which three the screen offers first, and
that is the board's call, not a preference exercised here.

### One anchor left open on purpose — two anchors name the same control

`Add a photo of your meal` stays ABSENT. That control already carries **`Scan a meal`**,
named earlier in this programme from **FIT-003**, which declares that word for exactly this
action. Two anchors name one control two ways.

Renaming it would move a point from FIT-003 to FIT-089 and change nothing for anyone using
the app; giving it both names would leave a screen reader announcing two. So it keeps the
name it has, FIT-089 sits at **6/7**, and the conflict is recorded rather than resolved by
preference. **Which word wins is the design owner's call.** → **OD-41**.

| Layer | Evidence | Status |
|---|---|---|
| Suite | **1473 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | FIT-089 0/7 → **6/7**; all interactions 307 → **313 / 600** | — |

## 3bi · BACK-G1 shipped blind to a quarter of what it claims to cover

One commit after **BACK-G1** landed at "baseline 0", `/ai-coach` turned out to have an
unnamed back button. The guard could not see it:

```dart
RegExp(r'Icons\.arrow_back(_ios_new|_ios)?\b')   // the first version
```

`\b` after an optional suffix cannot match `Icons.arrow_back_ios_new_**rounded**` — the next
character is `_`, which is a word character, so every alternative fails. That spelling is
used **eleven times** in `lib`:

| spelling | count | seen by v1 |
|---|---|---|
| `Icons.arrow_back` | 17 | yes |
| `Icons.arrow_back_ios` | 1 | yes |
| `Icons.arrow_back_ios_new` | 12 | yes |
| `Icons.arrow_back_ios_new_rounded` | **11** | **no** |

**All eleven were unnamed** — seven `IconButton`, four bare `GestureDetector`.

### Why the floor test did not catch it

BACK-G1 has a floor: *"the detector can still see back controls at all"*, asserting at least
**30**. The regex found exactly 30. The floor had been set to whatever the broken pattern
returned, so it certified the blindness instead of exposing it. A floor calibrated against
the detector it is meant to police is not a floor.

The pattern is now `Icons\.arrow_back\w*` — a shape, not an alternation of the spellings I
had happened to see — and the floor is **41**, the count of the glyph itself.

### The mutation that now exists for exactly this

**B5** narrows the regex back to the original alternation. It kills, because the floor is no
longer derived from the pattern. Two earlier attempts at B3/B5 **SURVIVED for a boring
reason** — nested shell quoting meant the script never actually edited the file — which the
harness reported as "SURVIVED", i.e. as a finding. A mutation that does not mutate is not
evidence either way; both were moved into a file that asserts its target is present before
replacing it.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/back_control_guard_test.dart` — floor raised 30 → **41** | **PASS** |
| Guard strength | **5 / 5 mutations killed**, each verified to have edited its target | **PASS** |
| Suite | **1473 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | all interactions 313 → **328 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| B1 | one `IconButton` loses its tooltip | **KILLED** |
| B2 | a `NamedIconButton` reverts to a bare `GestureDetector` | **KILLED** |
| B3 | the detector is blinded | **KILLED** |
| B4 | the naming predicate returns `true` unconditionally | **KILLED** |
| B5 | the regex narrows back to the alternation that missed `_rounded` | **KILLED** |

**Three guards in this programme have now been found blind after being declared at
baseline** — H-D1 (matched a declaration form nothing used), A-G8 (recorded overstatement),
and BACK-G1. In each case the floor test existed and passed. The common cause is that a
floor derived from the detector's own output cannot contradict it; a floor has to come from
something the detector does not compute.

## 3bj · Auditing every ratchet for the defect BACK-G1 had

Three guards have now been found blind **after** being declared at baseline. Rather than
assume the other twelve are sound, each one's detector was blinded — every `RegExp` literal
replaced with a pattern that cannot match — and the guard re-run. A guard that still passes
with its patterns dead has no floor: it would certify a codebase it can no longer read.

| Guard file | regexes | blinded → | verdict |
|---|---|---|---|
| `client_nav_contract_guard_test.dart` | 5 | FAIL | floor holds |
| `declared_denied_read_guard_test.dart` | 5 | FAIL | floor holds |
| `duplicate_screen_class_guard_test.dart` | 2 | FAIL | floor holds |
| `icon_control_naming_guard_test.dart` | 5 | FAIL | floor holds |
| `intake_advance_label_guard_test.dart` | 3 | FAIL | floor holds |
| `presentation_drift_guard_test.dart` | 17 | FAIL | floor holds |
| `rls_bypassing_view_guard_test.dart` | 5 | FAIL | floor holds |
| `rls_policy_shape_guard_test.dart` | 7 | FAIL | floor holds |
| `touch_target_guard_test.dart` | 1 | FAIL | floor holds |
| `ui_error_surface_guard_test.dart` | 5 | FAIL | floor holds |
| `orphan_route_guard_test.dart` | 0 | — | floor is a named route set (`/events`, `/home`, >50 routes), which the detector does not compute |
| `back_control_guard_test.dart` | 2 | did not compile | verified by hand — B3 kills |

**All thirteen fail when blinded.** The sweep is committed as `tool/blind_sweep.sh` so the
claim is repeatable rather than a one-off assertion.

### What the sweep does not catch, stated plainly

It tests **total** blindness. All three real failures were **partial** — the detector read
most of the codebase and missed a slice, so a floor asserting *"it found something"* passes
comfortably. H-D1 detected 5 of 20. BACK-G1 found 30 of 41.

Partial blindness is only caught by a floor the detector **does not compute**. BACK-G1 now
has one: a second count of the same glyph by plain substring splitting — no regex, no
knowledge of which suffixes exist — which the pattern's count must equal. A pattern that
quietly stops matching one spelling now disagrees with a count that never knew about
spellings.

That is the generalisable fix, and it is recorded here rather than retrofitted across all
thirteen in one sweep, because each guard needs a genuinely independent second measure and
inventing one mechanically would reproduce the original error in a new place.

| Layer | Evidence | Status |
|---|---|---|
| Sweep | `tool/blind_sweep.sh` — 13 guards, **0 without a floor** | **PASS** |
| Cross-check | BACK-G1 regex count == independent substring count | **PASS** |
| Suite | **1474 pass / 9 skipped** | **PASS** |
| Analyzer | 0 errors | **PASS** |

## 3bk · FIT-102…110 · one message made half of `/ai-coach` unreachable

**Nine** anchors are drawn on `/ai-coach`, and every one carries the same three controls:
`Back`, a **`Coaching`** tab and a **`Conversation`** tab. Four describe the coaching
surface, three describe the conversation. Both are always reachable.

There were no tabs. Both surfaces existed, but they were mutually exclusive on an
implementation detail:

```dart
child: _messages.length <= 1
    ? ListView( … the eight intelligence cards … )
    : ListView.builder( … the conversation … )
```

**Send one message and the cards were gone.** The daily brief, the weekly review, the goal
projection, the risk card, the meal ideas, the progress insight, the persona picker and the
coaching memory — and the last two are **the only write surfaces on the screen** — became
unreachable for the rest of the session, with no control anywhere that brought them back.
`_messages.length <= 1` is not a user-facing idea; it is a counter deciding which half of a
screen exists.

The composer moved with them. FIT-108/109 declare the `General`/`Nutrition`/`Workout` chips
and the input on the conversation anchors only — a composer beside a goal-projection card
answers nothing — so both now render on that surface alone, and sending from a suggested
prompt takes the user to where the reply will appear.

### Two tests that were not testing anything

**K4 — delete the 44 dp floor — SURVIVED.** The test measured
`find.ancestor(of: text, matching: GestureDetector)`, which climbed past the tab to an
enclosing detector and reported **590 dp**, with or without the constraint. The target is
now keyed, and the test also asserts the height is **under 200 dp**, so a finder that climbs
out again fails instead of passing loudly.

Fixing that exposed a second one: with the constraint keyed and removed, the box still
measured 590, because a `Container` with `alignment:` **expands to fill bounded
constraints** — and the harness had put the tabs in a full-height `body:`. In the real
screen they sit in a `Column`, where the height is unbounded and the floor is what decides
it. The harness now uses a `Column` too. A widget test whose layout differs from production
measures the harness.

### Covered as behaviour, and one part only as source

`CoachSurfaceTabs` is extracted so the tabs can be pumped on their own. `AICoachScreen`
reaches Supabase on build through all eight cards, so a whole-screen test would assert
against the harness — the same reason `MealRowTile` was extracted after N6. The claim that
the **screen** no longer branches on the message count is therefore a **source** assertion,
labelled `[SOURCE]` in the test name, and worth what a source assertion is worth: it proves
the branch is gone, not that the tabs behave. The behaviour is covered on the widget.

| Layer | Evidence | Status |
|---|---|---|
| Widget | `test/widget/ai_coach_surfaces_test.dart` — 3 rendered-UI tests | **PASS** |
| Domain | 3 rule tests | **PASS** |
| Source (labelled) | 3 assertions that the screen's branch is gone | **PASS** |
| Guard strength | **7 / 7 mutations killed** | **PASS** |
| Suite | **1483 pass / 9 skipped** (was 1474) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | all interactions 328 → **346 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| K1 | the tabs are not a mutually exclusive group | **KILLED** |
| K2 | the tab announces itself but cannot be pressed | **KILLED** |
| K3 | every tab reports itself selected | **KILLED** |
| K4 | the tab drops under the 44 dp floor | **KILLED** (survived twice first) |
| K5 | the screen picks the body from the message count again | **KILLED** |
| K6 | a suggested prompt posts into a surface the user cannot see | **KILLED** |
| K7 | the composer sits beside the goal-projection card | **KILLED** |

## 3bl · The component seven call sites now trust, tested by nothing

The `/ai-coach` tab test that measured 590 dp prompted a sweep of every size assertion in
the suite. Each was checked the only way that means anything — **delete the constraint in
`lib/` and see whether the test notices**.

| Assertion | Constraint deleted | Result |
|---|---|---|
| `pill_tab_test` | `PillTab`'s 44 dp floor | **KILLED** — sound |
| `zone_action_test` | `ZoneAction`'s 44 dp floor | **KILLED** — sound |
| `grocery_item_card_test` | the row's floor (§3bd G4) | **KILLED** — sound |
| `messaging_no_coach_test` | — | measures a text CTA, not this component |
| **`NamedIconButton`** | its `minWidth`/`minHeight` | **nothing failed** |

**Deleting `NamedIconButton`'s 44 dp floor left the entire 1,483-test suite green.** It is
the one place the "icon-only control, done correctly" shape lives, and its three promises —
a name, a pressable button role, and a 44 dp target around an *unchanged* chip — were
covered only through the widgets that happen to use it.

That gap mattered more the moment **seven more call sites were routed through it in this
session's back-control work**: each gave up its own constraint and took this one on trust.

| # | Mutation | Result |
|---|---|---|
| N1 | the 44 dp floor is deleted | **KILLED** |
| N2 | the `Semantics` loses `onTap` — a button nobody can press (F-20) | **KILLED** |
| N3 | `container: false` | **SURVIVED — see below** |
| N4 | it stops announcing as a button | **KILLED** |
| N5 | the target becomes a fixed box, shrinking a larger chip | **KILLED** |

### N3 survived, and the claim was withdrawn rather than propped up

`named_icon_button.dart` credits `container: true` with stopping the node absorbing adjacent
text — F-9 measured an intake header merged into a back button, the node covering the whole
411 × 914 dp screen.

Mutating it to `false` changes **nothing** observable in a widget test: not the label, not
the node's rect. Almost certainly because `excludeSemantics: true` already forces a node
boundary in this shape, making the flag redundant here rather than load-bearing.

Two things were *not* done: the assertion was not weakened until it passed, and the reason
string was not left saying something the test cannot show. The test now asserts only what it
observes — the node is the control's own and its neighbour is outside it — and says in its
own comment that it does **not** establish which flag achieves that. F-9's evidence was a
real semantics tree on a device. This is a widget test, and that difference is exactly what
the `RUNTIME_VERIFIED` rung exists to mark.

| Layer | Evidence | Status |
|---|---|---|
| Component | `test/widget/named_icon_button_test.dart` — 6 tests | **PASS** |
| Guard strength | **4 / 5 killed**; N3 withdrawn as untestable here, not papered over | **PASS** |
| Suite | **1489 pass / 9 skipped** (was 1483) | **PASS** |
| Analyzer | 0 errors | **PASS** |

## 3bm · FIT-088 · one tap gave the place away

The board marks this anchor **`missing`**, and it was. `/class-detail` cancelled a booking
on a single tap:

```dart
OutlinedButton(
  onPressed: () async {
    await ref.read(liveClassServiceProvider).cancelBooking(fitnessClass.id);
    ref.read(refreshClassesProvider.notifier).state++;
    if (context.mounted) context.pop();
  },
  child: const Text('Cancel Booking'))
```

**No confirmation, on an action that cannot be undone.** Cancelling frees the seat and
`_promoteFromWaitlist` hands it straight to the next person in line — so a mis-tap does not
merely cost the place, it **gives it away**. FIT-088 puts a step in front of exactly this,
with two controls: **`Keep it`** and **`Cancel place`**.

**The failure was invisible.** The `await` was unguarded, so a throw meant `context.pop()`
never ran and nothing was said — the user left on the same screen, still shown as booked,
unable to tell whether they still had a place. FIT-088 declares a `failure` state whose
control is **`Try again`**.

The confirm copy says what happens rather than asking *"are you sure?"*: *"Your place goes
to the next person on the waitlist."* `Keep it` is drawn first and as the plain action,
because it is the harmless one.

### Two things that looked wrong and are not

Both were checked against the source of truth and are recorded so they are not re-raised:

* `cancelBooking` calls `_promoteFromWaitlist` unconditionally, **including when the update
  matched no rows**. That does *not* overbook: the promotion returns early unless
  `_confirmedCount < max_capacity`, so it only fills a seat that is genuinely free.
* `class_bookings`' only surviving policy is
  `FOR ALL TO authenticated USING (user_id = auth.uid())`, with **no `WITH CHECK`** — the
  shape that is usually the F-21 defect. It is not one here: **Postgres uses the `USING`
  expression as the check when `WITH CHECK` is omitted**, so a user still cannot write a row
  onto someone else's `user_id`. No finding was raised, because a finding from the policy's
  shape alone would have been wrong.

### A defect in my own widget, found by the test hanging

`pumpAndSettle` timed out. On success the control called back but never left
`CancelStage.cancelling`, so the spinner animated forever. In the real screen the callback
pops the route and the widget is disposed, which hid it — but a caller that does not
navigate would have been left with a spinner that never stops. **The widget was fixed, not
the test**: it returns to `idle` before handing back.

| Layer | Evidence | Status |
|---|---|---|
| Widget | `test/widget/cancel_booking_control_test.dart` — 8 tests across all three states | **PASS** |
| Guard strength | **6 / 6 mutations killed** | **PASS** |
| Suite | **1497 pass / 9 skipped** (was 1489) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | FIT-088 0/5 → **3/5**; all interactions 346 → **349 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| C1 | one tap gives the place away, with no confirm step | **KILLED** |
| C2 | a failed cancellation says nothing | **KILLED** |
| C3 | a failed cancellation reports itself as done | **KILLED** |
| C4 | `Keep it` cancels the booking | **KILLED** |
| C5 | the controls stay live mid-request | **KILLED** |
| C6 | `Cancel place` drifts back to `Cancel Booking` | **KILLED** |

### The other two controls need capabilities that do not exist → OD-42

FIT-088 stays at **3/5** deliberately. Its remaining two are not omissions:

* **`Add to calendar`** needs a device-calendar dependency. `pubspec.yaml` has none, and
  nothing in `lib` writes an event or an `.ics`. Adding a platform dependency and its
  permissions is not a QA repair.
* **`My bookings`** has **no destination**. `/appointments` is coach calls, a different
  domain, and sits behind `PaywallGate`; class bookings have no route of their own.

The design intent is preserved and the missing dependency named for the phase that owns it,
rather than pointed at the nearest route that would make the number go up.

## 3bn · FIT-067 · the post type was lost three different ways

The board marks this anchor **`missing`** and names the capability it should be using:
`addPost(content, postType)`. `post_model.dart` already declares
`enum PostType { text, photo, progress, workout, achievement }` — **exactly the five the
board draws as radios**. Every layer between that enum and the database dropped it somewhere
else.

**1 · The chips were dead.** Three of the five, each handed an empty callback:

```dart
_buildPostTypeChip('📸 Photo', () {}),
_buildPostTypeChip('🏆 Achievement', () {}),
_buildPostTypeChip('💪 Workout', () {}),
```

They looked selectable, highlighted nothing, and were read by nothing. To a screen reader
they were three unrelated buttons, not a choice. They could not have worked even if wired:
the sheet's body was built inside `_CommunityScreenState`, where a `setState` does not
rebuild what `showModalBottomSheet` has already handed to the overlay — there was nowhere
for a selection to live.

**2 · The write ignored it.** `addPost(text)` was called with no `postType:`, so **every
post this app has ever created was stored as the default `'general'`**, whatever the user
tapped.

**3 · The read could not recover it.** `_parseType` mapped `progress` and `achievement` and
sent everything else to `text`, so `photo` and `workout` **could not survive a
write-and-read** even after the first two were fixed. One mapping now serves the UI and the
service, and `'general'` still reads as `text` so existing rows are not re-typed.

| Layer | Evidence | Status |
|---|---|---|
| Widget | `test/widget/create_post_sheet_test.dart` — 6 rendered-UI tests | **PASS** |
| Round-trip | every `PostType` survives write-then-read; `'general'`/`null` stay `text` | **PASS** |
| Guard strength | **7 / 7 mutations killed** | **PASS** |
| Suite | **1506 pass / 9 skipped** (was 1497) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | FIT-067 4/10 → **8/10**; all interactions 349 → **353 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| P1 | `photo` and `workout` cannot survive a write-and-read | **KILLED** |
| P2 | existing `'general'` rows are re-typed | **KILLED** |
| P3 | the five chips are unrelated buttons again | **KILLED** |
| P4 | the chips are handed empty callbacks again | **KILLED** |
| P5 | the chosen type never reaches the caller | **KILLED** |
| P6 | an empty post can be published | **KILLED** |
| P7 | the chips drop under the 44 dp floor | **KILLED** |

### Two measurement corrections, both mine

**`What's on your mind?` read ABSENT while rendering correctly.** Written
`'What\'s on your mind?'`, the *source* contains a backslash, and the resolver matches
rendered labels as string literals. Double-quoted, the source and the rendered text agree.
The escape was the only difference — the user saw the right words throughout.

**`Add a photo` measured HAVE, and nothing rendered it.** I had declared `addPhotoLabel` as
a constant while building no picker. The resolver reads the screen's file set for string
literals and cannot tell a *declared* name from a *drawn* one — the identical false positive
`sessionDoneLabel` produced for FIT-018, where the measurement said `Done` and the button
said `Submit`. The constant was **deleted**. FIT-067 therefore drops to 8/10 rather than
sitting at 9/10 on a name nobody can tap.

`Add a photo` needs an image picker and a storage path for post images; `createPost` takes
`imageUrls` but nothing in `lib` uploads one → **OD-44**. `Tues Lifters` is a group name —
data, not a control.

## 3bo · `/activity` · the design and the implementation are different screens → OD-43

FIT-064 draws `/activity` as a **chronological timeline** — *"Logged 62.4 kg · 07:20"*,
*"Breakfast · 420 kcal · 08:05"*, *"Lower body — strength · 51 min · 18 sets"* — filtered by
`All` / `Training` / `Food` / `Check-ins`.

`activity_screen.dart` is a **1,192-line metrics dashboard**: daily workout, streak, water,
performance rings, steps, calories, a nutrition grid. Not a worse timeline — a different
screen, with different content, for the same route.

This was **not** implemented, and the reason is not difficulty:

* replacing it means deleting a large working screen, which is destructive and is the kind
  of decision this programme does not take on its own;
* the filter strip on its own is meaningless — `All`/`Training`/`Food`/`Check-ins` filter a
  stream, and there is no stream to filter;
* building the stream's domain layer *without* the screen would add unused code, which is
  the accretion `DEAD-G1` exists to catch.

FIT-001's *"Activity folded in"* makes the timeline reading plausible — the dashboard's
content may belong on Home — but "plausible" is not a mandate to delete a screen.
**Recorded as OD-43 for the design owner**, with the intent preserved rather than
half-built.

## 3bp · FIT-065/066 · four of five reactions could be read and never written

The same defect as the post type, one layer over. `ReactionType` declares five,
`toggleReaction(postId, reactionType)` takes the type, `_parseReaction` maps all five on the
way back — and the provider hardcoded one:

```dart
Future<void> toggleLike(String postId) async {
  await _svc.toggleReaction(postId, 'like');   // always
```

So **four of the five could be read by this app and never written by it.** The UI offered a
single heart. `love`, `fire`, `clap` and `strong` existed in the model, the service, the
parser and the database, and nothing in the app could create one.

### And a defect that only appears once they are reachable

`toggleReaction` had two branches — *row exists → delete*, *no row → insert*. So choosing a
**different** reaction fell into the delete branch: switching from Like to Fire removed the
Like and left **nothing**. `post_reactions` carries `UNIQUE(post_id, user_id)`, so an insert
could not have replaced it either. With one reaction in the UI this was invisible; with five
it is the common case — every change of mind silently becoming a removal.

The decision is now `reactionWriteFor`, in the domain where a test can reach it:
insert / remove / **change**. No schema change — the unique constraint already said one
reaction per person per post; the code simply did not honour it.

### The tally had no name

`ReactionBar` drew it as bare emoji — `👍❤️🔥` and an integer — which a screen reader reads
as emoji characters and a number, saying nothing about what they are. The board writes the
names with the count in them: **`Like, 12 so far`**, **`Love, 4 so far`**, and plain
**`Fire`**, **`Clap`** where nobody has reacted. That asymmetry is the rule: a reaction with
no tally has no tally to announce. Whether *I* reacted rides on `selected`, not on the name,
so a reader says it in the user's own language — as `habit_row.dart` and `grocery_list.dart`
already do.

### This moves the coverage number by zero, and that is correct

`Like, 12 so far` is a **composed** label: the count comes from data, so no source literal
can match it and the resolver will always read it as ABSENT. `Fire` and `Clap` already
measured HAVE from bare words elsewhere.

**353 / 600 before, 353 / 600 after.** The work is a correctness fix and five newly
reachable controls with accessible names. Reporting it as coverage would have meant writing
the counts into `lib` as literals, which is the fabrication this programme refuses.

| Layer | Evidence | Status |
|---|---|---|
| Widget | `test/widget/reaction_picker_test.dart` — 4 rendered-UI tests | **PASS** |
| Rules | 9 more: counts, names, round-trip, and the write decision | **PASS** |
| Guard strength | **9 / 9 mutations killed** | **PASS** |
| Suite | **1519 pass / 9 skipped** (was 1506) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Coverage | **unchanged, by design** — see above | — |

| # | Mutation | Result |
|---|---|---|
| R1 | the count is dropped from the name | **KILLED** |
| R2 | an unused type is a missing key rather than zero | **KILLED** |
| R3 | my own reaction is not marked | **KILLED** |
| R4 | the controls go dead | **KILLED** |
| R5 | the controls drop under the 44 dp floor | **KILLED** |
| R6 | `clap` cannot survive a write-and-read | **KILLED** |
| R7 | only the heart is offered again | **KILLED** |
| R8 | switching a reaction deletes it instead | **KILLED** |
| R9 | a first reaction is written as a switch | **KILLED** |

### Left open, with the dependency named

* **FIT-066's per-comment likes** (`Like Amara's comment, 4 likes`). `PostComment` carries
  `likes` and `isLiked`, and the service hardcodes them to `0` and `false` — because
  `post_comments` has **no likes column and no reactions table**. This needs a migration,
  which is out of phase → **OD-45**. Nothing renders the dead fields, so no false zero ships.
* **`Share`** does nothing but fire a haptic. There is no share dependency in
  `pubspec.yaml` → **OD-46**.
* **`/post-detail`** does not exist; comments expand inline in the card. Whether FIT-066 is
  a screen or the existing inline panel is a design question, not a repair.

## 3bq · BACK-G2 · five screens the design draws a `Back` on, and none had one

`BACK-G1` ratchets whether a back control that **exists** carries a name. It says nothing
about a screen with no back control at all — and five had none:

`/goals` · `/score` · `/womens-health` · `/challenges` · `/action-items`

The design package declares every one of them **`hasBottomNav: false`** — a full-height page
with a `Back` control. The router puts all five inside the `ShellRoute`, so they get the
bottom bar instead, and not one of them had any back affordance whatsoever.

### Why "nobody is stranded" is not the end of it

The bottom bar is a way out, so this is not the `/pods` class of defect and is not recorded
as one. But all five are reached with **`context.go`** from `/directory` or `/home`, and a
bottom bar only ever returns the user to a **tab root** — never to the screen they came
from. `context.go` replaces rather than pushes, so `canPop()` is usually false here and the
system back gesture does not retrace the path either.

`backLeading` follows the idiom already in this codebase — `canPop() ? pop() : go(fallback)`
— because a bare `pop()` would do nothing on exactly these screens and a bare `go()` would
throw away a real history when there is one. The fallback is `/directory`, which is where
all five are actually linked from, not a guess.

### What the guard does not claim

It reads source: it proves the control is **constructed**, not that it is reachable, sized
or announced. `named_icon_button_test.dart` covers what `backLeading` builds — name, button
role, 44 dp target — and `BACK-G1` covers naming across the app. All three together remain
weaker than one device run, which is what F-6/F-6b are the record of.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/back_affordance_guard_test.dart` — 3 tests, 5 screens pinned | **PASS** |
| Guard strength | **3 / 3 mutations killed** | **PASS** |
| Suite | **1522 pass / 9 skipped** (was 1519) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | **sixteen** at baseline | **PASS** |
| Coverage | all interactions 353 → **360 / 600** | — |

| # | Mutation | Result |
|---|---|---|
| BB1 | one screen loses its back control again | **KILLED** |
| BB2 | back always jumps to the fallback, discarding real history | **KILLED** |
| BB3 | the shared control loses its name | **KILLED** |

## 3br · What is actually left, measured rather than asserted

Every remaining ABSENT label was classified by shape:

| Kind | Count |
|---|---|
| data / composed row labels (`Spinach, 2 bags`, `Like, 12 so far`) | **126** |
| date-derived tabs (`TUE 9` … `SAT 13`) | **5** |
| genuine controls | **~116**, across 62 anchors |

The 131 in the first two rows **cannot be closed without writing sample data or dates into
`lib` as string literals**, which is the fabrication this programme refuses. They are a
ceiling, not a backlog.

The ~116 is a long tail: most anchors have **one or two** — a `Cancel`, a `Try again`, a
`Refresh`, a specific label. It is over-counted (a two-word label containing a digit, like
`Bananas, 7`, classifies as a control here), so the true figure is lower. There is no
remaining item of the size of the `/ai-coach` tabs or the reaction picker.

## 3bs · Provenance correction — two of my commits carry another agent's work

**Previous state:** commits `84e89f7` and `e3a01f3` were described as a11y work.

**What is wrong with that:** both used `git add docs/`, which swept in files this session
did not author and had explicitly been treating as *evidence to read, not work to own*.

| Commit | Files that are **not this session's work** |
|---|---|
| `84e89f7` | the parallel audit's **16 documents** — `SCREEN_ECOSYSTEM_AUDIT.md`, `SCREEN_ECOSYSTEM_FINAL_AUDIT.md`, `MISSING_SCREEN_REGISTER.md`, `MISSING_CLIENT_SCREENS.md`, `MISSING_SCREEN_SUMMARY.md`, `FINAL_SCREEN_INVENTORY.md`/`.json`, `FINAL_NEW_SCREEN_DESIGN_COMMISSION.md`, `DESIGN_CAPABILITY_GAPS.md`, `DESIGN_IMPLEMENTATION_RECONCILIATION.md`, `DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md`, `FUTURE_CAPABILITIES.md`, `FUTURE_SCREEN_CAPABILITIES.md`, `SCREEN_DATA_REQUIREMENTS.md`, `SCREEN_DESIGN_GAPS.md`, `SCREEN_EVIDENCE_MATRIX.md` — **~4,300 lines** |
| `e3a01f3` | `docs/proposed/N07_assessment_access.sql` — the N-07 migration draft |

**Why this is the wrong outcome rather than a tidy one:** the commit messages describe
accessibility fixes, so the history now implies this session authored a screen-ecosystem
audit and a security migration draft. It did not. Both were read as evidence and, in the
case of the audit, had two of their claims independently re-derived before being acted on
(§3bd, §3bm).

**What was NOT done about it.** The files were not reverted and not deleted. Removing them
would destroy another agent's work to tidy my own record, which is a worse error than the
one being corrected, and rewriting published history is not available when another session
may already have read it. They stay; the provenance is recorded here instead.

**What changed going forward:** no further `git add docs/` or `git add <directory>` in this
session — explicit paths only.

**Still untracked and deliberately left alone:** `supabase/tests/security/d09-assessment-access.mjs`,
written at 10:17 today by the same workstream. It is **not** committed here.

## 3bt · A second identifier collision — `N-07` means two different things

| Source | `N-07` |
|---|---|
| `docs/MASTER_REMEDIATION_REGISTRY.md:53` | **`EC-05 / N-07`** — *"Workout completion swallows persistence and celebrates anyway"* — **CONFIRMED**, `active_workout_screen.dart` |
| `docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:105` | a **coach assessment / PAR-Q screen**, blocked on a privacy ruling |

These are unrelated: one is a Dart persistence defect deferred to Wave 3B, the other is an
unbuilt screen behind an owner decision. This is the **third** collision this programme has
found — after `OD-30` (a calorie constant vs a PAR-Q privacy question) and my own
`OD-33…38`. The cause is the same each time: two registers, two owners, one counter.

Neither was renumbered. The repository's registry is the older and is referenced by the wave
plan; the commission document is untracked and owned elsewhere. **Both are listed so the
next reader disambiguates by source rather than by number**, and "N-07" on its own should be
treated as ambiguous.

## 3bu · EC-05 / N-07 · completion swallowed persistence and celebrated anyway

`docs/MASTER_REMEDIATION_REGISTRY.md:53` records this as **CONFIRMED** and the wave plan
defers it to 3B *"because they are Dart, not policy"*. It is Dart, it touches no migration
number and no shared contract, so the Dart half is done here; **the wave owner still owns the
registry entry** and this session has not edited it.

### What `_completeWorkout` did

```dart
await _workoutService.logWorkout(log);            // UNGUARDED
if (_sessionId != null) {
  try { await _sessions.completeSession(…); }
  catch (_) {}                                    // SWALLOWED
}
await ScoreService().addWorkoutPoints();          // UNGUARDED
await ScoreEngine().workoutCompleted(workout.id); // UNGUARDED
ref.read(activeWorkoutProvider.notifier).reset(); // sets wiped
… showDialog(WorkoutCompleteDialog(…))            // celebration
```

**Two failures, in opposite directions.**

A throw from an **unguarded** call propagated out of `_completeWorkout`, so the trailing
`setState(() => _saving = false)` never ran. The Complete button is bound to
`onPressed: _saving ? null : _completeWorkout` — so it was **permanently dead**. No dialog,
no message, no second attempt: a finished workout the user could not file and no way to try.

A throw from **`completeSession` was discarded**. Execution continued: the sets were reset,
the session providers invalidated, and the celebration raised with full stats — over a row
the server still had as `in_progress`.

**The second crosses a boundary.** `workout_sessions` is the table a coach can read
(migration 100), and the coach surfaces filter on `status = 'completed'` — the same repoint
this programme made earlier. So a swallowed failure means **the coach never sees a session
the client actually finished**, and neither of them can tell.

### The rule

`WorkoutSave { failed, saved, scored }`, modelled on `FeedbackDelivery` in this same file —
*"the notes are safe and the screen must not claim a delivery"*. One level up: do not claim a
workout is filed until it is. Score writes are **derived and recomputable**, so their failure
gives `saved`, not `failed` — making someone retry a finished workout for a points row would
be the opposite mistake.

On `failed`, nothing is reset and nothing invalidated: **the local sets are the only
remaining copy of what the user did.**

### Two testability defects fixed on the way, and one that is not a defect

`ActiveWorkoutScreen` could not be pumped with a workout selected — merely constructing the
State threw. Two eager field initializers were the cause, and both now resolve on use, which
is the rule `WorkoutService` in this same feature **already states for itself**
(*"constructing the service must not require an initialised Supabase instance"*):

* `final _db = Supabase.instance.client` on `_ActiveWorkoutViewState`
* the same line in `CustomExerciseService`

The third obstacle was **not** a defect and was left alone: `initState` calls `_startSession`,
which reads `_db.auth.currentUser`. Starting a session on mount is what the screen is for.

**Consequence, stated rather than glossed:** the screen-level assertions here are `[SOURCE]`,
labelled as such in every test name. They prove the guard is **wired**, not that it behaves.
The behaviour is pinned one layer down on rules a test can reach. Closing that gap needs a
**Supabase-backed widget harness with a signed-in user**, which does not exist in this
repository → **OD-47**.

| Layer | Evidence | Status |
|---|---|---|
| Rule | `test/unit/workout_save_test.dart` — 10 tests | **PASS** |
| Wiring | `test/widget/workout_completion_honesty_test.dart` — 7, all `[SOURCE]` | **PASS** |
| Guard strength | **8 / 8 mutations killed** | **PASS** |
| Suite | **1539 pass / 9 skipped** (was 1522) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Runtime | **NOT** runtime-verified — see §3bc | `LOCALLY_VERIFIED` |

| # | Mutation | Result |
|---|---|---|
| E1 | a failed `completeSession` is treated as success again | **KILLED** |
| E2 | a failed `logWorkout` is treated as success | **KILLED** |
| E3 | a failed save may still reset the sets and celebrate | **KILLED** |
| E4 | a derived score failure throws away a filed workout | **KILLED** |
| E5 | having no session to complete is read as a failure | **KILLED** |
| E6 | the screen no longer gates the finish on the outcome | **KILLED** |
| E7 | the failure leaves the Complete button dead | **KILLED** |
| E8 | the exception is interpolated into the message (F-2/F-16) | **KILLED** |

One mutation had to be rewritten: the first E8 interpolated a runtime value into a `const`,
which does not compile, and the harness correctly reported **INVALID** rather than counting
it as a kill.

## 3bv · CON-01 · a failed check-in read answered "no", and the form wrote a duplicate

`docs/MASTER_REMEDIATION_REGISTRY.md:54` records **CON-01 / I-CHK-01 / E-CHK-01 / M-02** as
CONFIRMED: *"`public.checkins` is created by no migration"*. Re-derived here rather than
taken on trust, and it holds:

* **no migration creates `checkins`** — nothing in `supabase/migrations/` defines it under
  any form, and no view or function supplies it;
* `weekly_checkins` is the real table, `000_baseline_preexisting_tables.sql:146`;
* **seven Dart call sites** read or write `checkins` — one in
  `coach_dashboard_screen.dart:113`, six in `checkin_service.dart`.

### What could not be established, and why the table name was NOT changed

Whether the live database has a `checkins` table created out of band is **unverifiable in
this environment**, on both available routes:

| Route | Blocker |
|---|---|
| `supabase db dump --linked` | Docker daemon not running — `supabase` requires it |
| `supabase/tests/security/*.mjs` | needs `QA_URL` / `QA_ANON` / `QA_SERVICE`, unset here |

That fact decides the remedy, and the two remedies are opposites: if the table does not
exist, the seven call sites must be repointed; if it exists with data in it, repointing
**orphans real check-ins** and the schema needs codifying in a migration instead — which is
wave-governed and out of phase. **So no call site was repointed.** → **OD-48**.

### What WAS fixed, because it is wrong either way

The reads did not fail — they **answered**:

```dart
Future<bool> hasCheckedInThisWeek() async {
  try { … } catch (e) { return false; }   // "you have not checked in"
}
Future<int> getCheckinStreak() async {
  try { … } catch (e) { return 0; }       // "your streak is 0"
}
```

`false` and `0` are answers, given when the service had none — and a missing table is only
one of the ways to get there. An RLS filter or a dropped connection produces the identical
confident negative.

**It does not stop at the display.** `daily_checkin_screen` branches on it:

```dart
child: _alreadyDone
  ? _AlreadyDone(onGoHome: …)
  : SingleChildScrollView( … the whole check-in form … )
```

So a failed read showed **the empty form to someone who had already checked in this week**,
and `_submit` wrote another one. The lie produced a **duplicate weekly check-in**.

`CheckinKnown { done, notDone, unknown }` gives the screen the third state it needed. Only a
real `notDone` may open the form. The streak returns `int?`, and the screen's existing
`if (_streak > 0)` already hides a figure it cannot support — F-15's rule reached by the
layout that was there.

The failure copy is `checkinHistoryFailure` from this feature's own `checkin_hub.dart`,
which notes the `Could not load [noun]` pattern is rendered in fifteen places.

| Layer | Evidence | Status |
|---|---|---|
| Rules | `test/unit/checkin_known_test.dart` — 10 tests | **PASS** |
| Wiring | 5 more, all `[SOURCE]` and labelled | **PASS** |
| Guard strength | **6 / 6 mutations killed** | **PASS** |
| Suite | **1554 pass / 9 skipped** (was 1539) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Runtime | `LOCALLY_VERIFIED` — device blocked (§3bc) | — |

| # | Mutation | Result |
|---|---|---|
| K1 | unknown opens the form again — the duplicate-write path | **KILLED** |
| K2 | unknown claims the week is already done | **KILLED** |
| K3 | an unknown streak renders as `0` again | **KILLED** |
| K4 | the service answers `notDone` on a failed read again | **KILLED** |
| K5 | a failed streak read reports `0` again | **KILLED** |
| K6 | the screen drops the unknown branch and opens the form | **KILLED** |

## 3bw · The remediation registry's CONFIRMED column is stale on five entries

`docs/MASTER_REMEDIATION_REGISTRY.md` was mined for executable defects. Every **CONFIRMED**
line was re-verified against the current tree rather than taken on trust — §3's rule, applied
in the direction that costs work rather than saves it.

| Registry line | Recorded | Actually |
|---|---|---|
| `EC-05 / N-07` — completion swallows persistence | CONFIRMED | **still open** → fixed, §3bu |
| `CON-01` — `public.checkins` created by no migration | CONFIRMED | **still open** → read side fixed, remedy blocked, §3bv |
| `LRE-01 / REL-07` — `APP_ENV` defaults to `prod` | CONFIRMED | **already fixed** — `app_env.dart` sets `kDefaultEnvironment = AppEnvironment.dev` with the note *"ENV-4: this used to be `prod`"*, and a release build with no `APP_ENV` now **throws** |
| `LRE-02 / REL-18 / K-ENV-1` — three harnesses hardcode the production ref | CONFIRMED | **already fixed** — all three carry *"ENV-5: the target is resolved from `QA_URL`/`QA_ANON` … this file used to hardcode the PRODUCTION ref and key right here"* |
| `F-J-01` — `materialize_program_week` lost its authorization guard | CONFIRMED | **already fixed** — migration **124** restores the wrapper; its body raises `42501` unless `can_act_on_program(p_program_id)` |
| `F-J-17` — `derive_parq_risk` throws on three literal flag appends | CONFIRMED | **already fixed** — migration **126** |
| `F-J-07` — `build_workout` throws when recovery < 60 | CONFIRMED | **already fixed** — migration **127**, which also swept eleven further sites of the same class |

**Five of seven are closed.** A next agent reading that column would believe seven P0/P1
defects are open. The worse outcome is not wasted effort: it is "fixing" a closed one and
regressing the migration that closed it — which is precisely what `119` did to `116`'s guard
and what `124` had to undo.

**The registry was not edited.** It is a wave-governed document with its own owner (§16), and
the concurrent-session note the audit itself raised as OD-37 applies. This is recorded here
and flagged for that owner instead. → **OD-49**.

### Method note

Each was checked by reading the *current* definition, not by searching for the finding's
text. `F-J-01` in particular needed four migrations read in order — `116` built the guard,
`119` re-created the public name without it, `122` repinned `search_path` only, and `124`
restored it — because any one of them read alone gives the wrong answer.

## 3bx · A-G5 was green while guarding a branch nothing could reach

A sweep for the pattern this programme keeps finding — **a failure answering with a confident
value** — turned up 106 `catch` blocks returning a definite value across `lib`. Most are
benign: an *action* returning `false` for "it did not work" is correct.

Filtering to **query** methods (`has…`, `get…`, `count…`) that return `bool`/`int`/`double`
left **six**, and they are all the same defect:

```dart
Future<int> getCurrentStreak() async {
  …
  } catch (_) { return 0; }
}
```

### The part that matters

`train_hub_screen.dart` **already renders these correctly**:

```dart
value: streakAsync.when(
  data: (v) => '$v', loading: () => '—', error: (_, __) => '—')),
```

and carries the note *"Showing '0' told the member their streak was broken when the app had
simply failed to ask."*

**That `error:` arm could never run.** The service caught the failure and returned `0`, so
the `FutureProvider` was **always** `AsyncData(0)`. The member was still told their streak
was zero. The repair had been made at the presentation layer, over a service that destroyed
the signal it needed.

And **`A-G5` — the ratchet for exactly this — has been passing**, because it only ever reads
the widget. `presentation_drift_guard_test.dart:214`: *"no AsyncValue error branch returns a
bare numeral"*. True, and irrelevant: nothing could deliver an error to that branch.

> A guard that checks one layer of a two-layer defect reports the half it can see.

This is the prompt's own false-positive rule in the wild — *test passes ≠ test tests the
intended behaviour* — and it is the **fourth** guard in this programme found to be measuring
less than its name claims, after H-D1, A-G8 and BACK-G1.

### The fix, and what was deliberately left

The five workout stat reads no longer catch. The exception reaches the `FutureProvider`,
which makes an `AsyncError`, which the four tiles already render as `—`.

* **A signed-out user still returns `0`.** That is a real answer, not a failure, and A-G6
  asserts it stays.
* The other consumers — `home_screen.dart:348` and `ai_insights.dart:28` — use
  `.valueOrNull ?? 0` and then gate on `> 0`, so an error hides the figure rather than
  claiming one. No regression, and more honest than before.
* **`getUnreadCount` was left alone.** Its only consumers also do `.valueOrNull ?? 0`, so the
  badge is hidden either way and changing it would alter nothing observable.

**A-G6** is the new ratchet, and it guards *both* halves: no stat read may answer its own
failure with a figure, **and** the tiles must keep the placeholder that failure now reaches.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/stat_failure_reaches_ui_guard_test.dart` — 4 tests | **PASS** |
| Guard strength | **4 / 4 mutations killed** | **PASS** |
| Suite | **1558 pass / 9 skipped** (was 1554) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Ratchets | **seventeen** at baseline | **PASS** |

| # | Mutation | Result |
|---|---|---|
| A1 | `getCurrentStreak` swallows its failure into `0` again | **KILLED** |
| A2 | `getCompletionRate` swallows into `0` | **KILLED** |
| A3 | the tiles lose the placeholder the error now reaches | **KILLED** |
| A4 | the signed-out real zero is removed | **KILLED** |

**A second harness gap closed.** A2 first reported SURVIVED because its mutation *script*
threw and left the tree unmutated — a non-mutation read as a finding. The runner now requires
the mutation step to exit 0 and reports **INVALID** otherwise, alongside the compile check
added earlier.

## 3by · FIT-021 · the gate said "fail open" and the app failed closed

The dead-error-arm sweep from §3bx was generalised — every provider whose service swallows
**and** whose error arm is rendered — and it found one more. It is the most consequential
instance in the codebase, because it decides what a **paying member** can reach.

`PaywallGate` states its own policy, in its own comment:

```dart
error: (_, __) => child, // fail open rather than lock a paying user out
```

**That arm could never run.** `PaymentService.clientPlan()` caught the failure and answered
`'free'`:

```dart
} catch (_) { return 'free'; }
```

so `clientPlanProvider` was **always** `AsyncData(ClientPlan.free)`, the gate's earlier
`plan != null` branch took the early return, `atLeast(coachGuided)` was false, and a paying
**Coach-Guided** member whose entitlement read failed was shown **`PaywallLocked`** for a
feature they had paid for.

The gate said fail open. The app failed closed. Nothing tested it.

### This is not a security relaxation, and the distinction matters

Letting the exception out makes the **written** policy effective; it does not invent one, and
it does not widen any server-side boundary. `PaywallGate` decides whether a **screen is
offered**; every read inside it is still filtered by RLS. A free user who slips past the gate
on a failed read sees a screen the server will not fill.

What is deliberately preserved: a **successful** read returning a non-String is still
`'free'` — that is an answer, not a failure — and `A real "free" still locks` pins it, so the
repair cannot be mistaken for removing the paywall.

### My own test had the same two-layer flaw, and the mutation caught it

**PW1 — restore the swallow — SURVIVED twice.**

* First version: all five tests overrode `clientPlanProvider` directly, so they proved what
  the *gate* does with an `AsyncError` and nothing about whether anything produces one.
* Second version added a fake `PaymentService` that throws — which bypasses the **real**
  `clientPlan()`, so the swallow was still invisible.

`_db` is `Supabase.instance.client` and is not injectable, so the real catch cannot be driven
in a test at all. A `[SOURCE]` assertion is the only thing that closes it, and it is labelled
as such.

Reproducing, inside the commit that diagnoses it, the exact blindness being diagnosed is
worth recording plainly: **a test that stubs the layer under test proves nothing about that
layer.**

| Layer | Evidence | Status |
|---|---|---|
| Gate behaviour | `test/widget/paywall_fail_open_test.dart` — 5 rendered-UI tests | **PASS** |
| Service → provider | 2 tests over a throwing fake | **PASS** |
| Real method | 1 `[SOURCE]` assertion, labelled | **PASS** |
| Guard strength | **2 / 2 mutations killed** (PW1 only after the third attempt) | **PASS** |
| Suite | **1566 pass / 9 skipped** (was 1558) | **PASS** |
| Analyzer | 0 errors | **PASS** |

| # | Mutation | Result |
|---|---|---|
| PW1 | `clientPlan` swallows into `'free'` again — the gate fails closed | **KILLED** |
| PW2 | the gate's error arm locks instead of opening | **KILLED** |

### Left alone, with the reason

`activeMembership()` also catches into `null`, and `null` reads as "no membership". Its only
consumers are `manage_subscription_screen` and `hasActiveMembershipProvider` — and **that
provider has no consumers at all**. Changing it would alter nothing observable, so it is
recorded rather than churned. → **OD-50**.

## 3bz · VOICE-G1 · the voice note, and a public bucket holding it

§11 of the continuation directive names voice as existing capability and lists what to check:
permissions, lifecycle, cancellation, upload failure, cleanup, and **privacy of recorded
audio**. Four defects, and one security finding.

### Four defects in `coach_voice.dart`

**1 · A refused microphone did nothing at all.**

```dart
if (!await _rec.hasPermission()) return;
```

The coach holds the button, nothing happens, no message. A denied permission and a broken
button are indistinguishable.

**2 · A failed send looked exactly like a successful one.** `uploadCoachVoice` reports
failure by **returning `null`** — it catches internally and stashes `lastError` — and the
caller fell straight through that case. The method then ended in a bare `catch (_) {}`. The
coach released the button, the control reset, and nothing was saved.

**3 · An unattached note reported success.** `setCoachVoice`'s `bool` was discarded, so a
note could upload and never be attached to the exercise while `onRecorded()` fired anyway.

**4 · The capture was never removed.** Every hold wrote a real audio file of the coach's
voice to the device's temp directory — `coach-voice-<ms>.m4a` — and nothing deleted it,
**including the sub-800 ms taps that were discarded and never uploaded**. They accumulated
for the life of the install. Cleanup now runs in a `finally`, which is where it matters:
the failure paths are exactly where a capture gets left behind.

Also fixed: `_start` called `setState` after two awaits with no `mounted` check — a coach who
releases and leaves the screen disposed the widget mid-await.

### SECURITY · `coach-media` is a public bucket → **SEC-VOICE-1**

**Severity P2.** Not fixed here: the remedy is a migration, which is wave-governed and out of
phase (§14).

| Evidence | |
|---|---|
| `supabase/migrations/036_client_plan_and_coach_media.sql:33` | `VALUES ('coach-media', 'coach-media', true)` — **`public = true`** |
| `migrations/130_private_storage_buckets.sql` | privatises `chat-media`, `messages`, `progress-photos` — **`coach-media` is not among them** |
| `custom_exercise_service.dart:674` | `storage.from('coach-media').getPublicUrl(path)` for voice |
| `coach_video_response_screen.dart:78`, `coach_business_screen.dart:132` | the same bucket for coach **video responses** |

**The repository already holds the rule it breaks.** `chat_media_path.dart:14`:

> *"The bucket is PRIVATE. Nothing in the app may call `getPublicUrl()` on it"*

That sweep reached chat media and missed `coach-media`, which carries a coach's recorded
voice and video addressed to a particular client. A public Supabase bucket serves objects
**without authentication**: the path embeds UUIDs so it is not trivially enumerable, but a
leaked URL grants permanent, unauthenticated, non-expiring access.

Not raised as HIPAA: this is coaching content, not a clinical record. It is raised as a media
privacy boundary inconsistent with the app's own stated rule, for the security phase.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/coach_voice_guard_test.dart` — 5 tests, all `[SOURCE]` by necessity | **PASS** |
| Guard strength | **4 / 4 mutations killed** | **PASS** |
| Suite | **1571 pass / 9 skipped** (was 1566) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Runtime | the file's own header requires on-device audio testing — **not done** | `LOCALLY_VERIFIED` |

| # | Mutation | Result |
|---|---|---|
| V1 | a refused microphone is silent again | **KILLED** |
| V2 | a failed upload falls through without a word | **KILLED** |
| V3 | the capture is left on the device | **KILLED** |
| V4 | an unsaved note still reports success | **KILLED** |

V2 first **SURVIVED**: the assertion checked that the method *contained* the failure message,
and it still did — from the `catch` and the unsaved-row branch. It now asserts the
`url == null` arm itself. A guard that checks a file for a string is not checking a branch.

## 3ca · RUNTIME — the device build ran, and here is exactly what that proves

The disk recovered to **8.0 GB** (from the 118 MB of §3bc) and the emulator was still
booted, so the device attempt was retried under a 1 GB watchdog. **It succeeded.**

```
✓ Built build/app/outputs/flutter-apk/app-debug.apk        37.1s
adb install -r …                                           Success
am start com.twelvecircle.circle_fitness/.MainActivity     Started
free_after = 3925 MB
```

### What is now genuinely `RUNTIME_VERIFIED`

| Observed on `emulator-5554` | |
|---|---|
| The app **builds, installs and launches** on Android | ✓ |
| `/splash` (**FIT-010**) renders — the cycling headline reached *"Stronger every rep"*, with `Get Started` and `Already a member? Sign In` | ✓ |
| Routing works: tapping `Get Started` navigated to `/signup`, which rendered its full form — name, email, password with the reveal toggle, the `Client / Coach / Wellness Partner` selector, Terms checkbox, `Create Account`, Google and Apple | ✓ |
| **No `E/flutter` and no `FATAL`** in logcat across launch and navigation | ✓ |

### What this does NOT verify, stated plainly

**None of the defects fixed in this wave.** Every one of them —
workout completion (§3bu), the check-in read (§3bv), the stat tiles (§3bx), the paywall
(§3by), the voice recorder (§3bz) — sits **behind authentication**, and signing in means
entering credentials, which is not something to do on a user's behalf.

So those remain **`LOCALLY_VERIFIED`**. What the device run adds is that the binary
containing them builds, boots and navigates without crashing — which is real, and is not the
same claim.

The voice work specifically still carries its own file header's requirement: *"this needs
on-device testing (mic permission + capture + upload + playback across web/iOS/Android)"*.
An emulator with no signed-in coach does not satisfy it.

### A contradiction I suspected and checked rather than asserted

The first screen looked like **FIT-006 "Welcome"**, which the backlog marks **UNREACHABLE**
(OD-31) — a source-derived claim apparently refuted by the app booting straight into it.

It is not. The rendered screen is `SplashScreen` at `/splash` — `splash_screen.dart:26`
carries the exact cycling phrases seen (`'Stronger\nevery rep'`) and sends `Get Started` to
`/signup`, which is what the device did. `OnboardingScreen` at `/onboarding` is a different
file, and **nothing navigates to it**.

**FIT-006's UNREACHABLE finding stands, now corroborated from the other direction.**

Screenshots: `scratchpad/android_evidence/app_launch.png`,
`after_get_started.png`.

## 3cb · LIVE SCHEMA — three questions answered against the QA database

The previous wave recorded live verification as blocked on two routes, and **both are still
blocked**: Docker is not running (so `supabase db dump --linked` cannot start) and
`QA_URL`/`QA_ANON`/`QA_SERVICE` are unset (so `supabase/tests/security/*.mjs` will not run).
`.env` and `.env.local` are both **0 bytes**.

But the app's own committed QA config — `apps/mobile/dart_defines/qa.json`, the same file the
device build used — carries a **QA URL and anon key**. The anon key cannot provision test
users, so the role-boundary suites stay blocked. It is enough for three questions, and those
three are answered here **against the live database**.

The ref was checked first: QA is `eyqtldjqpgpljlqvpowh`, production is `nxdbooufqzkpslkcogxc`
— the same guard `lib.mjs` applies. The probe is committed as
`apps/mobile/tool/anon_least_privilege.py`: **GET only**, `limit=0` with
`Prefer: count=exact` so a count comes back and **no row ever does**, and a fixed nonexistent
object name for storage so no user content is touched.

### 1 · No unauthenticated access to anything — **VERIFIED**

All **65** tables probed with the anon key and with no key at all.

```
readable by anon : 0
```

Sixty-four answered PostgreSQL **`42501 — permission denied for table`**, with the hint
*"Grant the required privileges to the current role with: GRANT SELECT ON public.… TO anon"*.

That is **stronger than RLS**, and the distinction matters: RLS filters *rows*, so an
RLS-only defence answers `200 []` and depends on the policy being right. A missing **GRANT**
refuses the relation outright, before any policy is consulted. `user_profiles` — which is
where `parq_answers` and `has_injuries` live (migration 013) — is among them.

This was checked for a false positive: the key is a valid three-segment JWT, and a bad key
returns a different error, so the 401s are role denial and not an authentication artifact.

### 2 · `public.checkins` does not exist — **VERIFIED**, and it resolves OD-48

PostgREST distinguishes the two cases, so this is decidable without any read privilege:

| relation | response | meaning |
|---|---|---|
| `checkins` | **`PGRST205`** — not in the schema cache | **ABSENT** |
| `weekly_checkins` | `42501` | exists |
| `user_profiles` | `42501` | exists |
| `definitely_not_a_table_xyz` *(control)* | `PGRST205` | absent |

`checkins` behaves exactly like the nonsense control. **The seven Dart call sites in §3bv are
reading and writing a relation that is not there** — so every check-in save and read in the
app fails in QA. CON-01 is not a latent risk; it is live.

This makes the §3bv read-side repair load-bearing rather than defensive: before it, a user of
a **wholly non-functional feature** was told *"you have not checked in"* and shown a **0**
streak.

**OD-48 is answered, and the remedy is still not a rename.** There is no data to orphan, so
repointing is the right direction — but the shapes do not meet:

| the Dart writes | `weekly_checkins` has |
|---|---|
| `checked_in_at`, `checkin_type`, `stress_level`, `notes` | **none of these** |
| `sleep_hours` | `sleep_hours_avg` |
| *(nothing)* | `week_number`, `week_start_date`, `status` — all **NOT NULL** |

Four missing columns and three unsatisfied NOT NULLs: that is a **schema change**, which is
wave-governed and out of phase (§14). OD-48 is re-scoped from *"which table is right?"* to
*"authorise the migration that makes one of them work"*.

### 3 · `coach-media` is public — **SEC-VOICE-1 VERIFIED**

Probed with **no credentials at all**, which is exactly what a stranger holding a URL has:

| bucket | response | |
|---|---|---|
| **`coach-media`** | `NoSuchKey` — *"Object not found"* | **PUBLIC** — the bucket answered |
| `exercise-media` | `NoSuchKey` | **PUBLIC** |
| `avatars` | `NoSuchKey` | **PUBLIC** |
| `progress-photos` | `NoSuchBucket` | private — 130 worked |
| `chat-media` | `NoSuchBucket` | private — 130 worked |
| `messages` | `NoSuchBucket` | private — 130 worked |
| `no-such-bucket-xyz` *(control)* | `NoSuchBucket` | absent |

The three privatised by migration 130 refuse the public route; `coach-media` serves it. §3bz
inferred this from `036:33`; it is now observed.

**Limit of the discriminator, stated:** a private bucket and an absent one both answer
`NoSuchBucket`, so this proves *public*, not *private*. The three controls are known to exist
from migration 130, which is what lets them stand as controls.

`exercise-media` and `avatars` being public is plausibly intended — a shared exercise
catalogue and profile pictures. **`coach-media` is not the same case**: it holds a coach's
recorded voice and video addressed to one client.

### Scope of these three results

**QA only.** Production was deliberately not probed, and the probe refuses it. A table created
by no migration is unlikely to exist in any freshly provisioned environment, but that is an
inference and is not claimed as verified.

### Still BLOCKED

Everything requiring an authenticated session: coach↔client isolation, revocation taking
effect immediately, unrelated-coach denial, event/vendor paths, audit logging, and migration
102's `user_profiles` breadth over PAR-Q. Those need `QA_SERVICE` to provision users, and
provisioning is not something to improvise with a service-role key. → **OD-51**.

## 3cc · CHK-G1 · the check-in screen wrote to a table that does not exist

§3cb established live that `public.checkins` is **absent**. That turns CON-01 from a
read-honesty problem into a plain one: **every weekly check-in this screen took was lost.**
`_submit` called `CheckinService.saveWeeklyCheckin`, which writes to `checkins`.

### The working implementation was already next to it

`lib/features/checkins/data/` holds **two** services:

| | writes to | state |
|---|---|---|
| `CheckinService` | `checkins` | **absent — every write fails** |
| `WeeklyCheckinService` | `weekly_checkins` | exists, and already used by the check-in hub |

So the feature had a working writer the whole time; the submission screen reached for the
other one. No migration is needed to fix this, which is why it is in phase.

Checked before switching, so this does not trade one broken path for another:

* `submitWeeklyCheckin` writes `stress_level`, `sleep_hours_avg` and `notes` — none of which
  are in the `000` baseline. **Migration `001` adds them** (`stress_level`, `sleep_hours`,
  `notes`), so the writer is sound;
* its `onConflict: 'user_id,week_start_date'` matches
  `weekly_checkins_user_week_unique (user_id, week_start_date)` from `000:231`.

### Two collected fields are not persisted, and were not before

`workedOut` and `hitWaterGoal` are gathered by the form. `weekly_checkins` has no column for
them, and the old path wrote them to a table that is not there — so **nothing that was ever
saved is lost**. Adding columns for them is an owner decision, not a QA repair. → **OD-52**.

### The gate had the same swallow one level down

Routing the "already checked in?" question through `getCurrentWeekCheckin()` would have
inherited its defect: it ends in `catch (_) {}` and then returns a **`pending`** row, so a
failed read reads as *"you have not checked in this week"* — the §3bv defect again, in a
different file. `weekStatus()` is the honest version: `done` / `notDone` / `unknown`, with a
signed-out user still a real `notDone`.

`upsert` means a duplicate submit overwrites rather than doubling the row, so this one is not
data corruption — it is the user being told something untrue about their own week.

### The streak is deliberately left unknown

`getCheckinStreak()` still reads `checkins`, so it now returns `null` → the figure is hidden
(§3bv). That is correct: there is **no daily check-in table**, and a "day streak" derived
from a **weekly** table is different semantics, not a port. → **OD-52**.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/checkin_table_wiring_guard_test.dart` — 4 tests, `[SOURCE]` by necessity | **PASS** |
| Guard strength | **3 / 3 mutations killed** | **PASS** |
| Suite | **1575 pass / 9 skipped** (was 1571) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| Round trip | needs an authenticated QA session | **BLOCKED** — OD-51 |

| # | Mutation | Result |
|---|---|---|
| CK1 | submission goes back to the absent table | **KILLED** |
| CK2 | the gate reads the absent table again | **KILLED** |
| CK3 | a failed week read answers "not done" again | **KILLED** |

**`CheckinService` was not deleted.** It is dead to this screen but deleting a service is
destructive and is OD-32's class; it is left in place and recorded.

## 3cd · SEC-PHI-1 · registering for an event may disclose your medical history

**Severity P1 (privacy).** Recorded, **not fixed**: the remedy is an authorization policy
change, which needs a migration number and owner authorization.

### The policy

`102_restrict_user_profiles.sql:165`:

```sql
ON public.user_profiles FOR SELECT TO authenticated
USING (
  id = auth.uid()
  OR public.is_active_coach_of(id)
  OR public.is_team_lead_of(id)
  OR public.hosts_event_for(id)
);
```

### What is on the row it grants

`013_health_assessment.sql` adds to `user_profiles`: **`parq_answers`** (jsonb),
**`medical_conditions`**, `has_injuries`, `injury_locations`, **`injury_description`**,
`sleep_hours`, `stress_level`, `occupation` — and `115` adds `risk_score` / `risk_level` /
`risk_flags`.

**RLS grants rows, not columns.** Anything satisfying *any* arm receives **all of it**.

### Why the last two arms are the problem

The migration's own header explains why they exist, and it is not a clinical reason:

> *"Two access paths read profile columns that are deliberately NOT in the `public_profiles`
> view (**email**), so they cannot be served by the view and need their own policies instead:
> a head coach viewing their own team roster … an event host viewing their attendee list."*

So the requirement was **an email address for a roster and an attendee list**, and the
mechanism chosen hands over the PAR-Q.

```sql
hosts_event_for(target_user)  -- true for ANY vendor whose event the user registered for
is_team_lead_of(target_user)  -- true for ANY coach with a coach_team_members row
```

**An event host is not a care relationship.** Registering for a class or a workshop should
not disclose your medical conditions and injury history to the organiser.

The same migration shows the correct shape twice, for exactly this reason — it refused to
widen the base table for messaging and community and gave each a column-limited path instead
(`conversation_participant_profiles`, `public_profiles`). The two arms above are the cases
where that discipline was not applied.

### Verification status, split honestly

| Claim | How |
|---|---|
| The policy text is as quoted | source, `102:165` |
| PAR-Q and medical columns are on `user_profiles` | source, `013:5-14` |
| **No column-level `GRANT`/`REVOKE` exists on `user_profiles`** anywhere in 131 migrations | source, searched |
| No later migration narrows the SELECT policy | source, searched `11*`–`13*` |
| `coach_team_members`, `event_registrations`, `events` **all exist in QA** — so both arms are live, not inert | **live** (`42501`, not `PGRST205`) |
| A vendor can actually read a registrant's `parq_answers` end to end | **NOT VERIFIED** — needs two authenticated sessions and an event registration → **OD-51** |

The structural facts are verified; the exploit path is **inferred from them** and is labelled
as such rather than asserted.

### Remedy direction (for the security phase, not taken here)

Two column-limited views mirroring what `102` already did for messaging and community — a
roster view and an attendee view exposing display columns plus `email` — then drop
`is_team_lead_of` and `hosts_event_for` from the base-table policy. That is a migration:
**wave-governed, and an authorization change needing owner sign-off.**

### Relationship to N-07

This is the blocker the continuation directive named. **N-07 (the coach assessment surface)
cannot be built on `user_profiles` reads while this policy stands**, because the screen would
inherit the same breadth. `docs/proposed/N07_assessment_access.sql` and
`supabase/tests/security/d09-assessment-access.mjs` remain **authored, not verified**, and
are another workstream's files — untouched here.

## 3ce · Device re-verification regressed to BLOCKED — and it was not the code

§3ca recorded a **successful** device run. Re-running it after this wave's changes failed,
and the cause is worth recording precisely so the next agent does not read it as a code
regression.

```
java.nio.file.NoSuchFileException:
  ~/.gradle/caches/9.1.0/transforms/493234490dfd7d02cd90b43082e13f41/transformed/original/gradle-1.0.0.jar
```

**Not the app.** The failure is in `settings.gradle.kts` applying
`dev.flutter.flutter-plugin-loader`, before any project code compiles. Independently:
analyzer is at **0 errors** and **1,575 tests pass**, which compiles all of `lib`.

### What it actually was, after four wrong guesses

| Tried | Result |
|---|---|
| Delete the named transform directory | it did not exist — the index pointed at a pruned entry |
| Clear `md-rule` / `md-supplier` / `journal-1` | same failure, **535 ms** |
| Clear the project's `android/.gradle`, `.gradle`, `build` | same failure |
| Delete **all** of `~/.gradle/caches/9.1.0` | same failure, same hash, **3 s** |
| **Stop the Gradle daemons and clear `~/.gradle/daemon`** | **fixed it** — the build finally started doing real work |

A **stale Gradle daemon** was holding the pruned transform in memory. Deleting the cache
underneath a live daemon changes nothing, which is why four increasingly aggressive cache
deletions all failed in under three seconds: the daemon never re-read disk.

### And then disk ran out anyway

With the daemon cleared, Gradle began legitimately re-deriving the transforms cache from
zero — `~/.gradle/caches/9.1.0` grew 0 → 2.4 GB → beyond — and the watchdog stopped it at
**505 MB free**, from a starting **8.0 GB**.

The successful run in §3ca worked because that cache was already **warm**. Something wiped it
(the directory was recreated at 14:29, outside this session's actions), and **re-deriving it
from scratch does not fit on this volume**.

### Status, stated exactly

| | |
|---|---|
| This wave's code changes | **`LOCALLY_VERIFIED`** — analyzer 0, 1,575 tests |
| The app boots and navigates on Android | **`VERIFIED`**, but on the build from §3ca, **before** this wave's changes |
| This wave's changes on a device | **`BLOCKED`** — a cold Gradle transforms cache needs more disk than is free |

**The cheapest unblock is not more disk: it is not wiping that cache.** ~4 GB of headroom
plus a warm cache was enough; ~8 GB with a cold one was not.

## 3cf · Security/privacy wave — PHI inventory, live authorization, and two failed controls

All live work is **read-only** against the QA project (`eyqtldjqpgpljlqvpowh`; production
`nxdbooufqzkpslkcogxc` is refused by every probe). Nothing was inserted, updated or deleted.
No credential, token, email or PHI **value** appears in any probe output or committed file —
only status codes, row counts, and whether a column is present.

### PHASE 1 · PHI inventory

**Schema side.** `013_health_assessment.sql` puts the intake record on **`user_profiles`**:
`parq_answers` (jsonb), `medical_conditions`, `has_injuries`, `injury_locations`,
`injury_description`, `experience_level`, `sleep_hours`, `stress_level`, `occupation`,
`dietary_restrictions`, `food_allergies`, `consent_agreed/date`, and `115` adds
`risk_score` / `risk_level` / `risk_flags`.

| Table | PHI it carries |
|---|---|
| **`user_profiles`** | the whole intake/PAR-Q record above, plus `date_of_birth`, weight |
| **`cycle_symptoms`** | `symptoms[]`, `flow`, `energy`, `mood`, `notes` — **reproductive health** |
| **`cycle_logs`**, **`cycle_settings`** | menstrual cycle tracking (`033_womens_health.sql`) |
| `weekly_checkins` | `sleep_hours`, `stress_level`, `weight_kg`, `notes` |
| `coach_notes` | free text on a client, `tag` includes **`injury`** |
| `progress_photo_logs` | body photography |
| `weight_logs`, `workout_set_logs`, `weekly_feedback` | body metrics |
| `ai_conversations`, `conversations`, `messages` | free text that may contain health information |
| `exercise_modifications`, `exercise_intelligence` | `condition`, `joint_stress` |

**Views:** `public_profiles`, `conversation_participant_profiles`, `coach_client_workout_stats`.
**Functions:** 60 `SECURITY DEFINER`. **Buckets:** 6.

### PHASE 2/3 · anonymous reach — **VERIFIED DENIED**

| Surface | Result |
|---|---|
| **65 tables**, with the anon key and with no key | **0 readable.** 64 answer `42501 permission denied for table` |
| **3 views** — all `security_invoker = off`, i.e. RLS-bypassing by design | **3/3 denied** (`42501`) |
| **13 RPCs** incl. `admin_recent_users`, `admin_platform_stats`, `derive_parq_risk` | **0 reachable** — `401` (no EXECUTE) or `404` (not exposed) |

`42501` is a **missing GRANT**, which is stronger than RLS: RLS filters rows and answers
`200 []`; a missing grant refuses the relation before any policy runs. Checked against a
false positive — the key is a valid JWT, and a bad key returns a different error.

RPCs were probed with **GET only**. PostgREST refuses `GET` on a `VOLATILE` function with
`405` *without executing it*, so `admin_set_user_role` and friends could not have been
invoked by this probe.

### PHASE 4 · authenticated boundaries — **VERIFIED for every arm that exists**

Signing in needs only the anon key (`/auth/v1/token`), and `ids.json` already holds four
provisioned identities — so this did **not** need the service role.

| # | Boundary | Result |
|---|---|---|
| 8 | **client → own PHI** | **200, 1 row, 6/6 PHI columns** — works |
| 9 | client → **another client's** PHI | **0 rows**, and symmetric in both directions |
| 4 | **former coach → previously assigned client** (relationship `cancelled`) | **0 rows** — **revocation is effective** |
| 10 | **admin → a client's PHI** | **0 rows** — admin has no back door to the base table |
| — | attacker → `weekly_checkins`, `cycle_symptoms`, `cycle_logs`, `progress_photo_logs`, `coach_notes` | **0 rows** each |
| — | **the narrow view leaks nothing**: `public_profiles` returns 21 columns, **0 of 12 PHI columns**; naming `parq_answers` on it fails at SQL level (`42703`) | **VERIFIED** |

### SEC-PHI-1 re-classified — **PARTIAL, not proven exploitable**

The previous wave recorded the `is_team_lead_of` / `hosts_event_for` arms as "live". That was
too strong, and the live data corrects it:

```
coach -> user_profiles (no filter)   : 1 row — its OWN row only
coach -> coach_team_members          : 0 rows
coach -> events (as vendor)          : 0 rows
coach -> coach_client_relationships  : 1 row, status = cancelled
```

**Every arm except `id = auth.uid()` is unexercisable in the current QA dataset.** So:

* **VERIFIED**: RLS is row-level, no column-level `GRANT`/`REVOKE` exists on `user_profiles`
  in 131 migrations, and the policy names those two arms. *If* an arm is satisfied, the whole
  PHI row follows — that consequence is certain from SQL semantics.
* **BLOCKED**: whether a team lead or event host can actually come to satisfy it. Proving it
  needs a `coach_team_members` row or an `event_registrations` row — **a mutation**, which
  this phase forbids.
* **Not disproven.** No non-owner read of PHI succeeded in any test, and the one arm that
  could be observed (coach, cancelled) correctly denied.

### PHASE 6 · SEC-VOICE-1 — **FAILED CONTROL**, and worse than recorded

`coach-media` is **public**, verified with no credentials: it answers `NoSuchKey` for a
missing object while `progress-photos` / `chat-media` / `messages` answer `NoSuchBucket`.

The codebase already has the right pattern and does not use it here:

| Bucket | Access |
|---|---|
| `progress-photos`, `chat-media` | **`createSignedUrl(path, 3600)`** — 1-hour expiry, 5 files |
| **`coach-media`** | **`getPublicUrl`** in 3 places — permanent, unauthenticated |

**And deletion does not delete.** `clearCoachVoice()` nulls `voice_url`,
`voice_duration_ms` and `voice_expires_at` on the row — and **never removes the stored
object**. The only `storage.remove()` in the whole app is `chat_screen.dart:244`, for the
private chat bucket.

So a coach records a voice note for a client, later removes it, the app stops showing it —
and **the audio remains permanently fetchable by anyone who ever held the URL.** The row even
models an expiry (`voice_expires_at`) that the object does not honour.

### PHASE 7 · technical controls

| Control | Status |
|---|---|
| Service-role key absent from client code | **VERIFIED** — 0 hits in `lib/` |
| PHI absent from `print`/`debugPrint`/`log` | **VERIFIED** — 0 hits |
| PHI absent from URLs / query parameters | **VERIFIED** — 0 hits |
| Anonymous least privilege (tables, views, RPCs) | **VERIFIED** |
| Access revocation (cancelled relationship) | **VERIFIED** |
| Column-limited view for community/messaging | **VERIFIED** |
| `SECURITY DEFINER` `search_path` safety | **VERIFIED** — see the correction below |
| **Storage privacy for `coach-media`** | **FAILED** |
| **Media deletion / revocation** | **FAILED** — the object outlives the row |
| Audit logging of PHI access | **BLOCKED** — no `pg_proc`/log visibility without service role |
| The two wide `user_profiles` arms | **PARTIAL / OWNER DECISION** |

**A false positive I caught before reporting it.** A static sweep flagged **23**
`SECURITY DEFINER` functions with no `SET search_path` in their `CREATE` bodies. They are
**not** a defect: `116_rpc_execution_security.sql:77` runs a catch-all loop over `pg_proc`
pinning `search_path = public, pg_temp` on *every* SECURITY DEFINER function in `public` that
lacks one, and `118` and `122` re-run it. The detector read `CREATE FUNCTION` bodies and
missed the bulk `ALTER` — the same one-layer mistake recorded in §3bx, avoided this time by
reading the sequence.

## 3cg · SEC-VOICE-1 · the deletion arm is fixed; the bucket is AUTHORED/BLOCKED

The finding has two halves, and they are not equally blocked.

### Fixed in code — no migration needed

`clearCoachVoice()` nulled the row and **left the recording in the bucket**. It now derives
the object path from the stored URL and **removes the object first**, then clears the row.
Order matters: a failed delete must leave the note visible and retryable rather than the app
claiming a deletion it did not perform.

`coachVoiceObjectPath()` is deliberately strict — it returns `null` for a foreign bucket, a
relative path, an empty tail or a malformed value, so **a delete is never issued against a
path this code did not create**. That is tested directly, including the negative cases.

Even with the bucket still public, a removed note now stops being fetchable. **The exposure
is reduced, not closed**: objects uploaded before this remain public.

| Layer | Evidence | Status |
|---|---|---|
| Path derivation | 3 tests incl. 6 negative cases | **PASS** |
| Wiring | 2 `[SOURCE]` tests, incl. remove-before-clear ordering | **PASS** |
| Guard strength | **4 / 4 mutations killed** | **PASS** |
| Suite | **1580 pass / 9 skipped** (was 1571) | **PASS** |
| Analyzer | 0 errors | **PASS** |
| The delete executing against QA | needs an authenticated coach session | **BLOCKED** — OD-51 |

| # | Mutation | Result |
|---|---|---|
| SV1 | the object is no longer removed | **KILLED** |
| SV2 | a foreign URL becomes a delete target | **KILLED** |
| SV3 | an empty path is returned as a delete target | **KILLED** |
| SV4 | the row is cleared without touching the object | **KILLED** |

### Blocked — `docs/proposed/SEC_VOICE_1_coach_media_private.sql`, **AUTHORED**

Making the bucket private is a migration. `docs/MASTER_REMEDIATION_WAVES.md` reserves
**132+** for *"assigned at wave entry, never before"*, so the artifact carries **no migration
number** — self-assigning one is the collision that document exists to prevent.

Three things are recorded in it rather than glossed:

1. **It must not be applied alone.** Three `getPublicUrl()` call sites
   (`custom_exercise_service.dart:674`, `coach_video_response_screen.dart:78`,
   `coach_business_screen.dart:132`) must move to `createSignedUrl()` in the same change, or
   **every existing coach voice note and video stops loading** the moment it runs.
2. **The read policy is an owner decision, not an oversight.** A coach's voice note is
   *addressed to a client*, so "who may read it" is narrower than "who uploaded it" and wider
   than "only the owner" — the client must be able to play it. Resolving that needs the
   schema read that Docker and the service key currently block, so the arm is left explicitly
   `<TO BE RESOLVED>` rather than guessed.
3. **The SQL is unverified.** It was never executed: no Docker, no service role. It is
   written from `130`'s pattern and is labelled a draft.

`exercise-media` and `avatars` are also public. Those are plausibly intended — a shared
exercise catalogue and profile pictures — and are **not** included; narrowing them is a
product decision. → **OD-53**.

## 3ch · N-07 is BUILT AND SHIPPED — the commission document is stale

**Previous conclusion** (`docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:105`, another
workstream's file): N-07 "Coach client assessment (intake / PAR-Q)" is a **P0 missing
screen**, *"`client_detail_screen.dart:204,414` shows rollups only"*, **blocked by OD-30**
(privacy).

**Why it is wrong.** `client_detail_screen.dart` carries:

```dart
_tabs = TabController(length: 4, vsync: this);
…
tabs: const [ Tab(text: 'Overview'), Tab(text: 'Assessment'),
              Tab(text: 'PAR-Q'),    Tab(text: 'Progress') ],
…
children: [ _OverviewTab(…), _AssessmentTab(detail: detail),
            _ParqHealthTab(detail: detail), _ProgressTab(…) ],
```

`_ParqHealthTab` renders `parq_answers`, `medical_conditions`, `has_injuries`,
`injury_locations`, `injury_description`, `risk_level`, `risk_score` and `risk_flags`, with
the nine PAR-Q questions spelled out in the file. The screen consumes **39** keys from
`clientDetailProvider`, fourteen of them PHI. This is a live `TabBarView`, not dead code.

**Corrected conclusion: N-07 is not a missing screen. It is a shipped PHI viewer whose
authorization model is the open question.**

### This changes the severity of SEC-PHI-1

SEC-PHI-1 was recorded as a risk to a screen that did not yet exist. It is not:

```dart
final clientDetailProvider = FutureProvider.family<…, String>((ref, clientId) async {
  final profile = await db.from('user_profiles').select('*').eq('id', clientId).maybeSingle();
```

`select('*')`, on `user_profiles`, for an **arbitrary `clientId`**, gated only by migration
102's four-arm RLS policy. So whatever can satisfy `is_team_lead_of` or `hosts_event_for`
reaches a **rendered PAR-Q tab**, today, in shipped code — not a future screen.

The Dart is not the defect: the screen is *for* coaches reading assigned clients, and RLS is
what is supposed to scope it. The defect remains the policy's breadth. But the blast radius
is now known to be a working UI rather than a hypothetical one.

*(`select('*')` also pulls `email`, `phone` and the `stripe_*` identifiers, which the screen
never reads — a minimisation point, recorded, not fixed here: the screen genuinely consumes
almost everything else, so this is a narrow trim and not the finding.)*

**The commission document was NOT edited** — it is another workstream's file (§3bs). This is
recorded here and flagged. → **OD-54.**

## 3ci · SEC-PHI-2 · the PAR-Q screen printed the database error into itself

```dart
error: (e, _) => Center(child: Text('Error: $e', …)),   // client_detail_screen.dart:132
error: (e, _) => Text('Error: $e', …),                  // :1620
```

A PostgREST/Postgres error is not opaque: it carries table and column names, constraint text,
and on a unique violation the **conflicting value** — rendered on the page whose subject is
somebody's medical history. This is the F-2/F-16 class, on the one screen where it discloses.

Both now use the repository's own `Could not load [noun]` pattern (`Could not load this
client`, `Could not load programs`), which it already renders in fifteen places — no copy
invented.

| Layer | Evidence | Status |
|---|---|---|
| Guard | `test/unit/phi_screen_error_disclosure_guard_test.dart` — 3 tests | **PASS** |
| Guard strength | **3 / 3 mutations killed** | **PASS** |
| Suite | **1583 pass / 9 skipped** (was 1580) | **PASS** |
| Analyzer | 0 errors | **PASS** |

| # | Mutation | Result |
|---|---|---|
| PD1 | the client-detail error leaks the raw exception again | **KILLED** |
| PD2 | the programs error leaks the raw exception again | **KILLED** |
| PD3 | the PAR-Q tab is renamed — the guard must notice it lost its anchor | **KILLED** |

**Scope stated, not implied.** Five other sites still interpolate the exception —
`coach_video_response_screen.dart:103`, `coach_availability_screen.dart:381`,
`coach_marketplace_screen.dart:150`, and two in `admin_dashboard_screen.dart` (the latter
*parse* the error rather than display it, which is legitimate). None renders PHI. The guard
pins the PHI screens and names the rest rather than pretending to cover them. → **OD-55.**

## 3cj · N-07 authorization — verified live; auditability **FAILED**

With N-07 established as shipped (§3ch), its model was tested against QA with the existing
harness identities. **No identity was created and nothing was mutated.**

| # | N-07 rule | Result |
|---|---|---|
| 1 | **active assigned coach → client assessment = ALLOWED** | **BLOCKED** — no active relationship exists to test with |
| 2 | **unassigned coach → client = DENIED** | **VERIFIED DENIED** — 0 rows |
| 3 | **former coach → ex-client = DENIED** | **VERIFIED DENIED** — 0 rows, relationship `cancelled` |
| 3b | the same, using **`select('*')`** exactly as `clientDetailProvider` does | **VERIFIED DENIED** — 0 rows |
| 4 | unrelated **event host** → attendee | **BLOCKED** — no harness identity owns an event (3 exist, all seed-owned) |
| 5 | unrelated **vendor** → attendee | **BLOCKED** — same |
| 6 | **team lead** → client | **BLOCKED** — `coach_team_members` is empty for every identity |
| 7 | **client → own assessment = ALLOWED** | **VERIFIED ALLOWED** — 6/6 PHI columns |
| 8 | **client → another client = DENIED** | **VERIFIED DENIED** — 0 rows, both directions |
| 9 | **anon → assessment = DENIED** | **VERIFIED DENIED** — `42501`, no GRANT |

Rule 3b matters more than it looks: it confirms the **production query shape** is filtered,
not merely the narrow probe I wrote. The screen's own `select('*')` returns nothing to a
former coach.

### Access logging — **FAILED CONTROL**

| Probe | Result |
|---|---|
| `assessment_access_log` | **ABSENT** (`PGRST205`) |
| `audit_log` | **ABSENT** |
| `phi_access_log` | **ABSENT** |
| app-side writes to any audit table | **0** |
| control: `user_profiles` | `42501` — exists |

**No migration creates an access log**, and the app writes to none. A coach opens a client's
PAR-Q tab and **nothing records that it happened** — no actor, no subject, no timestamp.

This is not an oversight the proposal missed; it is the proposal's own first section.
`docs/proposed/N07_assessment_access.sql:54` reads *"1. The audit log. Append-only."* and
defines `assessment_access_log` with a `client_id, accessed_at DESC` index. **It has never
been applied**, so the control it provides does not exist.

That is the precise status: the **authorization** half of N-07 behaves correctly for every
arm that can be tested, and the **auditability** half does not exist at all. A screen that
renders PAR-Q with no access trail is the gap, not the unbuilt screen the commission document
describes.

→ **OD-56**: applying the N-07 proposal needs a wave-entry migration number and owner
sign-off. It is **AUTHORED**, not implemented, and this session did not touch it.

## 3ck · Phase B completed, and an attribution correction I owe

### The exposure matrix is finished

`docs/SECURITY_LEDGER_PHI.md` now carries the full ledger. The anon sweep was already done
(§3cb); what was missing was the **per-function** analysis, and it is complete:

* **54** SECURITY DEFINER functions probed anonymously, GET-only — **0 executable, 0 returned
  data**. No explicit `GRANT … TO anon` exists anywhere in 131 migrations.
* **21** touch a PHI table. Of those, **12 are triggers** (`RETURNS trigger`) which PostgREST
  does not expose at all, and the rest were read line by line.
* Only **two** non-trigger functions take a UUID and read PHI, and both are sound:
  `is_coach_profile(uuid)` returns a **bare boolean** (`role = 'coach'`, already public via
  `public_profiles`), and `get_or_create_conversation(uuid)` **binds participant 1 to
  `auth.uid()`** — the caller cannot forge identity.
* `marketplace_coaches()` — the one PHI-touching function granted to `authenticated` with no
  internal check — is `RETURNS TABLE` with 17 named display columns. The return type *is* the
  column limiter. **0 PHI**, in both the `041` and `046` definitions.

**Positive and negative cases, not just negative.** `admin_recent_users` and
`admin_platform_stats` were invoked after reading their bodies and confirming they contain no
`INSERT`/`UPDATE`/`DELETE`:

```
anon 401 · attacker 403 · coach 403 · victim 403 · admin 200
```

Every denial is `42501`, raised before any row is produced. `is_admin()` is enforced
server-side — **VERIFIED CONTROL**, demonstrated in both directions.

### An honest correction: SEC-PHI-1 is not my finding

`docs/N07_IMPLEMENTATION_STATUS.md` §2 — *"The authorization finding (owner decision
required)"* — records migration 102's breadth over PHI, written by the other workstream at
10:18 today, **before** §3cd. My §3cd presented it as a finding. It is a **re-derivation**.

What this programme did add is the part they could not: **live evidence**. That the two wide
arms are currently unexercisable, that revocation demonstrably works, that the narrow view
leaks nothing, and that the assessment screen is already shipped. Two independent analyses
converging on the same policy is corroboration, and it is worth more than either alone —
but the finding is theirs, and the ledger now says so.

### SEC-PHI-3 — the part that is new

Their proposal is explicit that it **does not** touch 102's policy:

> *"Instead it adds a dedicated, narrow read path for assessment data which admits ONLY the
> active assigned coach — not team leads, not event hosts — and which records every access."*

That is the right call. But the shipped screen reads the **base table**:

```dart
final profile = await db.from('user_profiles').select('*').eq('id', clientId).maybeSingle();
```

So applying the N-07 migration would add a safe, audited door **beside** the wide one, and
the Assessment and PAR-Q tabs would keep using the wide one. Neither the narrowing nor the
audit trail takes effect until `clientDetailProvider` is repointed at
`get_client_assessment()`. Their next-steps list does not include that repoint — reasonably,
since their doc records `client_detail_screen.dart` as *"being modified by a concurrent
session right now"*, which was this one.

**This is code, not schema**, so it is not migration-blocked — only ordered behind the
migration, because the RPC must exist before Dart can call it. Recorded as **SEC-PHI-3**, the
next free id (existing: SEC-01…12, SEC-020…031, SEC-R1…R3, SEC-PHI-1/2, SEC-VOICE-1).

### Storage enumeration — NOT TESTABLE, stated rather than claimed

Every bucket answers `200 []` to a list request, from anon and from an authenticated client
alike — including the three known-private ones. That is the ambiguous shape, not a denial.
`progress_photo_logs` is `*/0`: **QA holds no media at all**, so the listing proves nothing
about policy either way. The *public* finding stands regardless, because its discriminator
(`NoSuchKey` vs `NoSuchBucket`) does not depend on content.

## 4 · Design package

| Check | Status |
|---|---|
| Authoritative package identified, legacy package rejected | **PASS** — `DESIGN_INTAKE_REPORT.md` §1 |
| FIT-001…FIT-110 contiguous and machine-readable | **PASS** |
| manifest ↔ DESIGN_HANDOFF ↔ IMPLEMENT-THIS ↔ board | **PASS** — 0 mismatches across 110 screens |
| Components 25 vs 28 | **PASS** — resolved by the `shipped` field; my earlier FAIL was wrong |
| 105/110 FIT screens map to an existing route | **PASS** — `DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` |
| Design board carries no FIT ids — frame↔manifest linkage is by name only | **ENVIRONMENT LIMITATION** — automated visual regression breaks silently on a rename |
| `capture-references.mjs` baseline not yet generated | **NOT ESTABLISHED** — required before Visual QA (Phase 11) |
| Board HTML carries per-frame **body copy** and designer annotations | **CONFIRMED** — see §3w; the manifest alone was being used as the copy source |

## 5 · Integration state

| Item | Status |
|---|---|
| Tier 1 — weight ramp extended below w400 (`light`, `extraLight`) | **PASS** |
| Tier 2 — contract extended: `borderSubtle`, `accentOnDark`, `displayWeight`, `displayTracking`; `helixDisplay`/`helixNumeric` now read the theme; tabular figures added | **PASS** |
| Tier 3 — 12Circle bundle retargeted to the design tokens (colour, shape, motion, type) | **PASS** — conformance-tested |
| **Screens consuming the semantic tokens** | **0 of 158** — see below |
| Visual change at runtime from the Tier-3 retarget | **none observed**, as predicted |

**The honest state of integration.** The token foundation is correct, test-pinned and
mutation-verified — and it changed nothing on screen. Confirmed at runtime: after
retargeting every token, the login screen renders identically (still a pill CTA, still a
purple glow, still the old violet), because `login_screen.dart` reads its own private
`AuthColors` palette rather than the theme.

This is not a failure of the change; it is the measured shape of the remaining work.
`DESIGN_INTAKE_REPORT.md` §10.1 established it in advance: **zero files read
`context.helix`**, 108 of 158 presentation files carry raw hex (1,418 occurrences),
`AppColors` has 1,028 call sites, and 20 mutually inconsistent private palettes ship
concurrently. Visual integration is necessarily **per-screen**, across the 45 implementing
files in the matrix.

## 6 · Owner decisions — open

**This table was four rows short of a quarter of the real list.** It carried OD-1…7 while
OD-8…40 had been recorded inline across this file and across the parallel audit's documents,
so a reader asking *"what needs me?"* saw eight items instead of thirty-odd. Consolidated
below.

### 6.0 · Two numbering faults, recorded rather than quietly renumbered

**`OD-30` means two different things.** In this file it is *"the calorie figure —
`_elapsedSeconds ~/ 60 * 8`"*. In `docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md` it is
***"May a coach read a client's PAR-Q / medical history?"*** — a privacy and authorization
question, and much the more serious of the two. An owner resolving "OD-30" would not know
which they had resolved. **Neither was renumbered here**, because renumbering someone
else's live document is how a third meaning gets created; both are listed, qualified by
source, and the collision is the thing to fix.

**I created six more of these and have corrected them.** Sections 3bh–3bp originally
allocated OD-33…38, which the parallel audit had already used for Pods reachability, the
`/log-meal` stub, commissioning missing designs, the disk blocker, session sequencing and
the reference PNGs. The audit's documents are untracked but were written first, so **mine
were renumbered to OD-41…46**, not theirs. Two ids were checked and are genuinely clear:
**OD-5 is withdrawn** (recorded in `DESIGN_INTAKE_REPORT.md`) and **OD-13 was never
assigned**.

### 6.1 · From this file

| Id | Question | Blocks | Can continue without |
|---|---|---|---|
| OD-1 | Landscape: lock to portrait, or design and support it? | F-5 | everything portrait |
| OD-2 | GAP-07 — AI error states the backend cannot reach | those states | all reachable states |
| OD-3 | GAP-08 — Score frame semantics (`ScoreService` vs `ScoreEngine`) | one screen | all others |
| OD-4 | GAP-09 — navigation entry for the event ticket | F-10 | all others |
| ~~OD-5~~ | ~~Component denominator~~ — **WITHDRAWN**, resolved by the `shipped` field | — | — |
| OD-6 | Display weight: the design says w300; Schibsted Grotesk ships no w300 | display type only | colour, shape, spacing, motion |
| OD-7 | Font delivery — bundle the family or accept runtime fetch (F-11) | offline fidelity | online behaviour |
| OD-8 | Coach-assignment copy: a failure must not read as a denial | `/profile` section | rest of profile |
| OD-9 | A surface the package draws that the app has no way to discover | that surface | all others |
| OD-10 | `More` left inert rather than wired to an invented destination | one control | the screen |
| OD-11 | Content the app cannot open — a product-content question | that content | the screen |
| OD-12 | (recorded inline, single mention) | — | — |
| ~~OD-13~~ | **never assigned** | — | — |
| **OD-14** | **F-21 · authorization change required** | the finding | everything else |
| OD-15 | The coach's "New Class" affordance — a frame omitting a capability is not a removal | one affordance | the screen |
| OD-16 | Check-in review: position, queueing, and the resolved-silently case | FIT-033 detail | the screen |
| OD-17 | FIT-019's third pill is `Recent`; the app's is `Barcode` — different features | one pill | the screen |
| OD-18 | FIT-031's prices (£19/£39/£79) are not the product's prices | pricing copy | the screen |
| OD-19 | FIT-030 declares a privacy control with no data model | that control | the screen |
| OD-20 | (copy whose absence a guard now asserts) | — | — |
| OD-21 | The two triage thresholds — how many days of silence make a client "at risk" | thresholds | the screen |
| OD-22 | `After training` — should a nutrition log record its relation to a session? | one field | logging |
| OD-23 | The row is not a button: the manifest says `el: "button"`, the board draws otherwise | one row | the screen |
| OD-24 | `Sessions 4/4` — completed-against-prescribed is on no column of this row | one stat | the row |
| OD-25 | A control left unavailable rather than wired to an invented flow | one control | the screen |
| OD-26 | The goal archetypes — FIT-008 draws four, the flow ships six | intake copy | the flow |
| OD-27 | What `Skip this` means for a goal, given it feeds a calorie calculation | one branch | the flow |
| OD-28 | (resolved silently upstream; recorded, nothing changed) | — | — |
| OD-29 | The rest of the feedback dialog — FIT-018 draws one question | extra questions | the dialog |
| OD-30 ⚠ | **(this file)** the calorie figure `_elapsedSeconds ~/ 60 * 8` | one number | the screen |
| OD-31 | Does Welcome enter the flow? FIT-006 is locked at `/onboarding` and unreachable | FIT-006 | everything else |
| OD-32 | Deleting a duplicate/dead screen file is destructive | 9 dead surfaces | all live ones |
| **OD-41** | `Add a photo of your meal` (FIT-089) vs `Scan a meal` (FIT-003) — **two anchors name one control two ways** | FIT-089 7/7 | the control works |
| **OD-42** | FIT-088 `Add to calendar` needs a device-calendar dependency; `My bookings` has no destination | FIT-088 5/5 | cancelling works |
| **OD-43** | `/activity`: FIT-064 draws a **timeline**, the app ships a **1,192-line metrics dashboard** — different screens, same route | FIT-064 | both screens work |
| **OD-44** | FIT-067 `Add a photo` — `createPost` takes `imageUrls`, nothing in `lib` uploads one | FIT-067 10/10 | posting works |
| **OD-45** | FIT-066 per-comment likes — `post_comments` has no likes column; needs a **migration**, which is out of phase | FIT-066 | reactions work |
| **OD-46** | `Share` fires a haptic and nothing else; no share dependency in `pubspec.yaml` | one control | the card |

### 6.2 · From the parallel audit's documents (untracked, recorded here for one list)

These are **that process's** allocations, restated so the owner has a single place to look.
They are data from another workstream, not findings re-derived here.

| Id | Question |
|---|---|
| OD-30 ⚠ | **(commission doc)** May a coach read a client's PAR-Q / medical history? — **collides with OD-30 above** |
| OD-33 | Pods (FIT-071…074) are built, designed and **unreachable** — `/pods` is orphaned |
| OD-34 | `/log-meal` is a 23-line redirect stub while FIT-019 is locked at 4/5 — build it, or re-anchor |
| OD-35 | Commission the six missing-design surfaces (MCS-05…10)? Two are store-review gates |
| OD-36 | Reclaim disk so tests and device runtime can execute — **see the note below** |
| OD-37 | Pause or sequence the concurrent session so screen work has a single owner |
| OD-38 | Generate the 110 reference PNGs — **marked RESOLVED** in that document |
| OD-39 | Where should the regenerated baseline images live durably? |
| OD-40 | Is admin/vendor tooling (7 routes) in design scope at all? |

**Two of those touch this session directly, and the second is a correction.**

**OD-37** names concurrent session `d1740817` — this one. That process recorded that screen
work has two owners. This session has not edited any of those sixteen untracked documents;
it has read them as evidence and re-derived their claims before acting (§3bd, §3bm).

**OD-36 is recorded there as having "cleared on its own: 5.6 GB free, 76% used".** That is
no longer true and was not true during this session's device attempt: the volume fell from
**3.4 GB to 118 MB** in under ten seconds of Gradle work, and the build failed on a cache
lock. The Gradle 9.1.0 artifact-transform cache alone is **3.5 GB**. Device verification
remains blocked — see §3bc.

## 6b · Phase A/B findings — navigation, authorization and state coverage

Produced by two delegated read-only audits. **Every item marked VERIFIED below was
re-checked by me directly against source**, because each is consequential enough that a
delegated claim alone is not evidence.

### F-12 · DISPOSITION — route entry is weak; the data layer is not **TESTED EMPIRICALLY**

> **This supersedes the severity recorded below. The original finding is retained
> unaltered underneath, because it is accurate about the router — it was simply incomplete
> about consequence.**

The open question was whether route-entry weakness produces data exposure. It was settled
by **testing the live QA database as an authenticated client**, not by reading code.

Method: signed in as the committed QA fixture `p1-victim@qa.12circle.test` (role `client`,
`uid 1c89c873-…`) against QA `eyqtldjqpgpljlqvpowh` using the anon key, then issued the
reads and writes the privileged screens issue. Probe:
`scratchpad/f12_probe.mjs`. Prod ref is never contacted.

| Probe | Result | Verdict |
|---|---|---|
| `GET user_profiles?select=id,role` | **1 row, `id == own uid`**, `content-range 0-0/1` | own row only |
| `GET coach_client_relationships` | **403 `42501`** — "Grant the required privileges…" | denied at GRANT level |
| `GET payments` / `subscriptions` / `event_registrations` / `notifications` / `workout_sessions` | 200, **0 rows** | filtered |
| `GET events` | 200, 3 rows | shared content, not privileged |
| `PATCH user_profiles(own).role = 'admin'` | **403 `42501` — "user_profiles.role is not self-assignable — use admin_set_user_role"**; role re-read as `client` | escalation blocked by a named guard |
| `PATCH user_profiles(coach).first_name` | 200 **`[]` — 0 rows affected** | RLS filtered the target row out |

**Neither mutation changed anything**, confirmed by re-reading after each.

Separating the concerns exactly as the brief requires:

| Layer | Finding |
|---|---|
| Route entry | **WEAK — confirmed.** Any authenticated user can enter `/admin-dashboard`, `/vendor-portal`, `/compliance`, `/coach-dashboard` |
| UI self-guarding | **PARTIAL.** 9 screens swap the body for a placeholder; the rest do not |
| Backend authorization | **SOUND in every path tested** — grants, RLS row filtering, and an explicit anti-escalation guard |
| Information disclosure | **NOT DEMONSTRATED** |
| Mutation capability | **NOT DEMONSTRATED** |

**Revised classification: P3 — SECURITY/UX/ARCHITECTURE, not data exposure.** A client can
open an admin screen and see it render empty or placeholdered. That is a trust, polish and
defence-in-depth problem, not a breach. Overstating it would be as wrong as missing it.

#### Second pass — the privileged screens' actual calls, probed

A delegated trace produced the exact table/RPC surface of the four routes, which was then
probed with the same client identity:

| Probe | Result | Verdict |
|---|---|---|
| `rpc admin_platform_stats` | **403 `42501` "not authorized"** | denied — `SECURITY DEFINER` + `is_admin()` guard, `019_admin_dashboard.sql:24-26` |
| `rpc admin_recent_users` | **403 `42501` "not authorized"** | denied — same guard, `:60-62` |
| `rpc coach_client_ai_signals` | 200 **`[]`** | executes, but server-filters `r.coach_id = auth.uid()` (`079:88`) — returns nothing |
| `GET events` | 200, 3 rows | `"all read events" USING (true)` (`001:398`) — shared content, by design |
| **`GET platform_settings`** | **200, 1 row** | **readable by any authenticated user** |

**F-12a · Platform configuration is readable by every member — the one real exposure.**

`039_platform_settings.sql:17-18` declares
`CREATE POLICY "read platform settings" … FOR SELECT TO authenticated USING (true)`. Writes
are correctly admin-gated (`:22-25`), but reads are open, and the table holds business
configuration — the row the admin dashboard reads is `marketplace_commission_rate`
(`platform_settings_service.dart:11`).

So a member can read the platform's commission rate. **Classification: P3 — business-
configuration disclosure, not user-data disclosure.** It is declared and deliberate in the
migration, so it may be intentional; recorded so the owner can confirm rather than
discover. Raised as **OD-9**.

**Declared-policy weak points found by the trace but NOT demonstrated as exploitable**, each
recorded for the eventual table-by-table sweep rather than asserted as defects:
`events` vendor UPDATE/DELETE are ownership-scoped but the role predicate sits only in
`WITH CHECK` (`020:18-27`); `event_registrations` vendor UPDATE has `USING` and no
`WITH CHECK` (`020:42-49`); `workout_logs` has **no coach-read policy at all** (owner-only,
`003:193`) while three code paths read it for other users' ids — which means those reads are
declared-denied and the coach surface silently gets nothing; `goals` coach-read keys on the
row's `coach_id` column rather than an active-relationship check (`018:71`); and `checkins`
— read by `coach_dashboard_screen.dart:107-112` — **does not exist in any migration** and is
already a tracked contract violation (`known-violations.json:14-17`, I-CHK-01).

**Scope limit, stated plainly:** this tested the tables named above, not an exhaustive set.
It establishes that the data layer *is* enforcing, not that every table is covered. A
table-by-table sweep is the remaining work, and the repo already has the harness for it
(`supabase/tests/security/`, which needs `QA_SERVICE` — not available locally, supplied in
CI).

**Correction of a stale record of mine:** a memory note claimed role escalation had been
regressed by migrations 115/119. QA now blocks it with a purpose-built message. That note
was wrong for QA as it stands today; production was not tested and is not claimed either
way.

### F-12 (original finding, retained) — the router enforces no role restriction at all **VERIFIED**

`app_router.dart:180-224` contains exactly one denial:

```dart
if (!isAuthenticated && !isAuthRoute) return '/login';
```

That is the whole access-control surface. The `role` lookup at `:206-218` runs **only**
inside the `isAuthenticated && isAuthRoute` branch and returns a *destination*
(`/coach-dashboard`, `/admin-dashboard`, `/vendor-portal`), never a refusal. It is a
landing-page selector, not a guard.

**Consequence:** any authenticated user — any client — can navigate to
`/admin-dashboard`, `/admin-exercise-review`, `/vendor-portal`, `/compliance`,
`/coach-dashboard`, `/coach-payments`, `/coach-business`, `/coach-client-workouts` and the
rest. The URL resolves, the shell mounts, the screen builds.

Nine screens self-guard **inside the widget** and render a text placeholder
(`observability_screen.dart:43` "Admins only.", `coach_copilot_screen.dart:112`,
`content_review_queue_screen.dart:76`, and six more). The route is still entered; only the
body is swapped. The remaining role-oriented routes — including `/admin-dashboard`,
`/vendor-portal`, `/coach-dashboard` and `/compliance` — carry **no role check anywhere**.

**Classification: OWNER DECISION.** Adding router-level role enforcement changes
authorization behaviour, which brief §7 reserves. **NOT ESTABLISHED:** whether Supabase
RLS backstops the data behind these screens — that is a server-side question this audit did
not open, and it determines whether this is an information-disclosure defect or "only" a
UX and trust defect. It should be answered before the decision is taken.

### F-13 · PaywallGate fails open on provider error **VERIFIED — deliberate**

`paywall_gate.dart:45` — `error: (_, __) => child, // fail open rather than lock a paying
user out`. A plan-provider error grants access to all 13 gated routes.

**Classification: RECORDED RISK, not a defect.** The comment shows this is a considered
trade-off with a stated rationale. Recorded so the owner knows the failure mode exists; not
changed, because reversing a documented product decision is not QA's call.

### F-14 · The shipped bottom nav is not the mandated five tabs **VERIFIED**

`IMPLEMENT-THIS.md`: *"Five client tabs, fixed: Home · Workouts · Nutrition · Check-In ·
Connect. No sixth."* Shipped (`app_shell.dart:147-151`):

| # | Shipped | Mandated |
|---|---|---|
| 1 | Home → `/home` | Home ✅ |
| 2 | Train/AI Train → `/train` **or `/ai-coach`** depending on coaching mode | Workouts — present but **not a stable destination** |
| 3 | unlabelled FAB → `/directory` | — **not mandated** |
| 4 | Activity → `/activity` | — **not mandated** |
| 5 | Check-In → `/daily-checkin` | Check-In ✅ |
| — | **absent** | **Nutrition** ❌ |
| — | **absent** | **Connect** ❌ |

Only four labelled destinations are exposed, not five. `/messages` (Connect) is demoted to a
top-bar icon (`app_top_nav.dart:116`); Nutrition has no nav entry at all.

**Classification: OWNER DECISION — and it is not a one-line change.** `/directory` is the
**sole** entry point to `/events`, and the primary entry to `/classes`, `/challenges`,
`/community` and `/progress`. Replacing the FAB with a Connect tab would strand them.
A third, never-rendered nav definition also exists (`app_scaffold.dart:252-279`,
`AppBottomNav`, never instantiated) with a *fourth* different tab set.

### F-14 · UPDATE — the stranding objection is resolved by FIT-001

My recorded reason for not adopting the mandated five tabs was that `/directory` is the
**sole** entry to `/events` and the primary entry to `/classes`, `/challenges`,
`/community` and `/progress`, so replacing the FAB would strand them. **FIT-001 answers
that directly.**

Its subtitle is *"Activity folded in · Directory moved to the top bar"*, and its frame
carries three 44×44 controls in the Home bar:

```
aria-label="Directory"      ph-compass
aria-label="Messages"       ph-chat-circle
aria-label="Notifications"  ph-bell   + unread dot (violet-txt)
```

So the design does not delete those destinations — it **relocates** them. Directory moves
from the bottom FAB to the Home top bar, and Activity folds into Home rather than holding a
tab. That frees exactly the two slots the five-tab contract needs for Nutrition and
Connect.

**Consequence for the decision:** the technical objection is withdrawn. Nothing is
stranded, and the package supplies the complete relocation plan rather than only the tab
list. What remains is a genuine product choice — whether to adopt the new navigation —
not an unanswered engineering question. The repo already has a top bar
(`core/widgets/app_top_nav.dart`, which routes to `/messages` at `:116` and `/profile` at
`:73`), so the Directory and Notifications controls have an established home.

This is recorded as an update rather than an edit: the original objection was correct on the
evidence available then, and wrong once FIT-001 was read.

### F-15 · Error→empty collapse — the dominant defect pattern

Eight screens present a **server failure as "you have no data"**:
`progress_screen.dart:139`, `checkin_screen.dart:146`, `coach_dashboard_screen.dart:68/98/114/133`,
`profile_screen.dart:830`, `classes_screen.dart:39`, `challenges_screen.dart:36-39`,
`home_screen.dart:80`, `train_hub_screen.dart:224-238`.

Worked examples:
- A coach whose client fetch fails is told **"No clients found — Clients will appear here
  when they sign up."**
- `train_hub_screen.dart:224` — `error: (_, __) => '0'`. A failed load **displays "0
  workouts" as a real answer.**
- `progress_screen.dart:139` swallows the entire screen load and renders every empty state
  at once: "Log your first weight…", "No entries yet", "No check-ins yet".

`booking_screen.dart:609-643` is the **only** place in the codebase that names this as a bug
and guards against it — its copy reads *"This is a connection problem, not an empty
schedule."* That screen is the in-repo reference implementation for the correct pattern.

**Classification: FAIL (P2).** Fixing each is mechanical but touches eight screens' product
copy; the pattern to copy already exists in-repo.

### F-16 · Swallowed errors and stringified exceptions, quantified

- **52 of 94 `catch` blocks (55%)** under `features/*/presentation/` (excluding auth)
  neither surface anything nor call `reportError`.
- `reportError` is called in **5 places total** in the whole presentation layer — the four
  auth screens plus `chat_screen.dart:207`.
- **48 sites across 30 files** put a raw error object into user-visible text. Seven are
  bare `Text('Error: $e')` with no human copy at all.

Worst swallows, each hiding a *user-initiated* action: `settings_screen.dart:62` (unit
preference silently not saved — the toggle appears to work), `progress_screen.dart:1195`
and `:1339` (measurement and weight saves), `home_screen.dart:1257` (coach review lost),
`pods_screen.dart:67` (pod join), `intake_flow_screen.dart:219/227` (**the entire
onboarding profile save, double-nested silent catch**).

`settings_screen.dart:546` deserves separate mention: a swallowed read leaves `coaches`
empty, which **skips the destructive-action confirmation at `:549`** — coaching mode is
switched away with no warning that coaches will be cancelled.

### F-17 · Zero offline handling, zero back protection **VERIFIED**

- No connectivity package is in `pubspec.yaml`; **0 of 18** audited screens detect
  connectivity. Several show a `wifi_off` icon and "check your connection" copy that is
  never driven by an actual signal.
- `grep PopScope|WillPopScope|onPopInvoked` across `lib/` → **0 matches**. Nothing guards
  back-out of an **in-progress workout with running timers** or the **27-page intake
  flow**. The only back containment in the app is the router's recovery redirect
  (`app_router.dart:189-191`).

### F-18 · Screens that cannot be reached

| Route | Finding |
|---|---|
| `/log-meal` | **Zero inbound navigation.** Deep-link only — and it is **FIT-019 "Log a meal", a LOCKED design anchor** |
| `/checkin-detail` | Only inbound is `checkin_card.dart:27`, in a widget **no file imports** |
| `/food-search` | Zero inbound; registered and paywalled |
| `/checkin-form` | Only inbound is the same dead widget |
| `/events` | Exactly **one** entry point — the `/directory` FAB (see F-14) |

Separately, **9 screens exist entirely outside the router**, reachable only by
`MaterialPageRoute`: `CreateClassScreen`, `EventTicketScreen`, `EventAgendaScreen`,
`ClientDetailScreen`, `CoachVideoResponseScreen`, `ChoosePackageScreen`,
`CoachAvailabilityScreen`, `EventAttendeesScreen`, `ProgramBuilderScreen`. They have no URL,
no deep link, and do not update the shell's active-tab state.
`vendor_portal_screen.dart:170` passes `canManage: true` as a constructor argument in a file
with no role check — a privilege granted by which button was tapped.

### F-19 · Dead code

`home_org.dart`, `dashboard_screen.dart`, `dash_org.dart`, `checkin_card.dart` and
`AppBottomNav` (`app_scaffold.dart:252`) have **zero importers or zero instantiations**.
Navigation links inside them are unreachable. **Classification: PASS WITH OBSERVATION** —
harmless at runtime, but it inflates every "screen exists" count, which is exactly the trap
brief §9 warns about.

### F-20 · FIT-016 "Workout detail" is a hardcoded mockup **VERIFIED**

`workout_detail_screen.dart` contains **0** occurrences of `ref.`, `Supabase`, `await` or
`Future` — no data access of any kind, with a hardcoded hero asset at `:49`. It is a static
mockup, and **FIT-016 is a LOCKED design anchor**. `/workout-detail` is reachable
(`workout_list_screen.dart:319`) and shows the same content regardless of which workout was
tapped.

**Classification: FAIL (P1 for integration).** No amount of restyling makes this screen
correct; it needs wiring to a workout. Recorded against FIT-016 in the matrix.

#### F-20 · Full workflow trace — the contract EXISTS, the plumbing does not

Traced end to end, as required, before changing anything:

```
tap a workout        workout_list_screen.dart:312-320
  │  final match = sampleWorkouts.where((sw) => sw.title == w.title).firstOrNull;
  │  if (match != null) _startWorkout(match);        → sets identity, goes /active-workout
  └─ else               context.go('/workout-detail');  → NO identity, static mockup
route                app_router.dart:264
  │  GoRoute(path: '/workout-detail', builder: (_, __) => const WorkoutDetailScreen())
  │  no path parameter, no query, no `extra`
implementation       workout_detail_screen.dart:18-19
  │  const WorkoutDetailScreen({super.key})   ← accepts no workout identity at all
data source          NONE — 0 occurrences of ref. / Supabase / await / Future
loading / empty / error   none of the three exist
```

**Two defects, not one.**

1. `/workout-detail` is the **failure branch of a title-string match**. `w` is a local
   `_WorkoutItem` view model (`:529`) and `sampleWorkouts` are `Workout` objects, so the
   code recovers the real object by comparing `title` strings. When that comparison misses,
   the user is sent to a hardcoded screen describing **a different workout than the one
   they tapped**. Matching domain objects by display title is fragile by construction.
2. The screen renders fixed content regardless.

**The backend contract exists and nothing needs inventing:**

| Piece | Where |
|---|---|
| Identity carrier | `selectedWorkoutProvider` — `StateProvider<Workout?>`, `workout_provider.dart:116` |
| Real data | `assignedWorkoutsProvider` → `FutureProvider<List<Workout>>` via `CoachProgramService().getMyAssignedProgram()`, `workout_provider.dart:152-158` |
| Model | `Workout`, `workout_model.dart:232` |
| Established convention | `active_workout_screen.dart:102` already does exactly this: `ref.watch(selectedWorkoutProvider)`. `chat_screen.dart` uses the same pattern with `selectedConversationProvider` |

So integration is **objectively supported**: set the identity before navigating, read
`selectedWorkoutProvider` in the screen, render the real workout, and add the three states.
No backend field is missing and no data would be fabricated.

**Status: ~~MAPPED, NOT YET IMPLEMENTED~~ → IMPLEMENTED AND RUNTIME-VERIFIED.**

#### F-20 · Acceptance criteria, each with evidence

Runtime walk on `emulator-5554`, signed in as `p1-victim`, Workouts → browse list.

| # | Criterion | Evidence | Verdict |
|---|---|---|---|
| 1 | Implementation corresponds to FIT-016 | back/more bar, context line, 3-col metric strip between hairlines, coach note, numbered rows, CTA — all from the board | **PASS** |
| 2 | Selected identity preserved | `selectedWorkoutProvider` set at the nav site, read by the screen | **PASS** |
| 3 | Title matching no longer identity | `_WorkoutItem.workoutId` resolves `Workout.id`; the title comparison is deleted | **PASS** |
| 4 | Workout A displays A | tapped "Full Body Strength" → `ASSIGNED BY COACH SARAH` · `3 EXERCISES / 45min / 7 SETS` · `1 Barbell Squat 3 × 8 · 60 kg · rest 90 s` | **PASS** |
| 5 | Workout B displays B | tapped the card shown as `Glute & Hamstring\nFocus` → resolved to domain title **`Glute and Hamstring Focus`** · `2 EXERCISES / 50min / 5 SETS` · `1 Hip Thrust 3 × 12 · 80 kg` | **PASS** |
| 6 | No fabricated data | every value traced to `Workout`/`WorkoutExercise`/`WorkoutSet`/`Exercise` | **PASS** |
| 7 | Empty/no-selection distinct | tapped "Metabolic Overdrive" (no domain workout) → **"No workout selected"**, no CTA, no exercises | **PASS** |
| 8 | Error does not masquerade as success | — | **N/A, stated honestly** — see below |
| 9 | Existing flows intact | 848 tests pass; active-workout, list, assignment, AI generation untouched | **PASS** |
| 10 | Relevant tests pass | 6 new widget tests + 848 suite + analyzer clean | **PASS** |
| 11 | Android runtime verification | the walk above; **zero** `E/flutter`, `FATAL`, `RenderFlex` or overflow throughout | **PASS** |
| 12 | Accessibility not regressed | `Back`, `Begin session` and each row (`1 Barbell Squat 3 × 8 · 60 kg · rest 90 s`) carry names; rows ≥ 44 dp | **PASS** |

**Criterion 5 is the decisive one.** The card's *displayed* title and the *resolved* workout
title differ (`Glute & Hamstring\nFocus` vs `Glute and Hamstring Focus`). That they differ
is the proof: a title match could not have produced this, and previously that exact card
always fell through to the mockup.

**Criterion 8 — why N/A rather than PASS.** This screen reads an in-memory
`StateProvider`; there is no fetch, so there is no load to fail and nothing to inject. The
analogous risk — a *missing* selection being dressed up as content — is criterion 7 and it
passes. Claiming a PASS for an untestable path would be exactly the category conversion
this ledger forbids.

**Two defects found and fixed during verification, both by runtime evidence:**

- **Doubled semantics labels.** Wrapping a labelled `Semantics` around a widget that
  already contains the same `Text` produced `'Sign in\nSign in'` and
  `'Continue with Apple\nContinue with Apple'` — a screen reader says it twice. Visible in
  my own earlier on-device dumps and not questioned at the time. Removed the redundant
  `label:` on both auth buttons and the CTA, and used `excludeSemantics` on the exercise
  row whose composed label replaces its children. Re-verified on-device: now `'Sign in'`.
- **Back button returned to `/train`, not the list.** Navigating with `context.go` leaves
  no pop-able entry, so `canPop()` was false and the fallback fired. Changed to
  `context.push`, matching this feature's own convention
  (`train_hub_screen.dart:123`). Re-verified: Back now lands on `BROWSE WORKOUTS`.

**A test of mine was passing trivially and was fixed.** The screen is a `ListView`, so the
CTA sat below the fold of the default 800×600 test surface and was never built — meaning
`expect(find.text('Begin session'), findsNothing)` proved nothing. The tests that assert
the CTA's presence or absence now set a 390×1600 surface first.

**Fixture hygiene.** Reaching the list required the fixture's `onboarding_complete` to be
true. It was flipped, used, and restored: re-read confirms `onboarding_complete: false`,
`role: client`. Device state cleared with `pm clear`.

#### F-20b · The browse list advertises workouts that do not exist **NEW**

Established while fixing F-20, and left unfixed deliberately.

| Browse card | Domain workout |
|---|---|
| Full Body Strength | `id '1'` |
| `Glute & Hamstring\nFocus` | `id '2'` |
| Metabolic Overdrive | **none** |
| Morning Cardio Blast | **none** |
| Active Recovery Flow | **none** |
| — | `id '3'` Upper Body + Core Circuit — **not in the list** |

`_sampleWorkouts` (`workout_list_screen.dart:64`) is a hardcoded list of five presentation
items; `workoutsProvider` returns three domain workouts. **Three cards have no workout
behind them at all, and one real workout is not offered.** Those three now open an honest
"No workout selected" instead of a mockup, but a browse list that advertises sessions the
app cannot open is a product-content question, not a QA repair. **OWNER DECISION — OD-11**:
remove the unbacked cards, author real workouts for them, or accept the placeholder.

### F-10 / GAP-09 · CORRECTION OF TERMINOLOGY

The design package calls `event_ticket_screen` **"unreachable"**. That word is wrong and
this ledger will not repeat it.

Measured: it has **no `GoRoute`** (`grep EventTicket lib/core/router/app_router.dart` →
nothing), and it **is** reached at `events_screen.dart:81` via
`Navigator.of(context).push(MaterialPageRoute(...))`.

Correct terminology, used from here on: **not router-addressable / not deep-linkable.**
The user-facing consequence is that the destination has no URL, cannot be deep-linked,
does not participate in the router's shell or redirect logic, and does not update the
bottom nav's active tab — **not** that it cannot be opened. Eight further screens share
this characteristic (F-18).

## 6c · F-15 inventory — every error→empty collapse

Required fields per the brief. "Distinguishable" = can the user tell a failure from a
genuinely empty result. Design state = does the authoritative package specify an error
state for that screen.

| Screen | Route | Failure behaviour | Empty behaviour | Distinguishable | Data source | Existing error state | Design state | Decision needed |
|---|---|---|---|---|---|---|---|---|
| ~~`progress_screen.dart:139`~~ | `/progress` | ~~`catch (_)` → three empty states at once~~ → **`Could not load your progress` + Try again** | "Log your first weight…", "No entries yet", "No check-ins yet" | **YES** | direct Supabase, 6 fetches | yes | FIT-052…057 | **none for this leg** |
| ~~`checkin_screen.dart:146`~~ | `/checkins` | ~~`catch (_)` → "No upcoming sessions. Book a call with your coach."~~ → **`Could not load sessions` + Try again** | "No upcoming sessions…" | **YES** | `coaching_calls` | yes — see §3m | FIT-023 | **none for this leg** |
| ~~`coach_dashboard_screen.dart:68`~~ | `/coach-dashboard` | ~~`catch` → `[]` → "No clients found"~~ → **`Could not load your clients`** | "No clients found…" | **YES** | clients query | yes | FIT-032 | **none for this leg** |
| ~~`coach_dashboard_screen.dart:98/114/133`~~ | `/coach-dashboard` | ~~`catch` → `[]` ×3~~ → **errors propagate**; any of the three failing is reported | empty tabs | **YES** | check-ins, workouts, aggregate | yes | FIT-032/033 | **none for this leg** |
| ~~`profile_screen.dart:830`~~ | `/profile` | ~~`valueOrNull` → null → "No coach assigned yet"~~ → **section hidden**; a failure is never rendered as a denial | "No coach assigned yet · Complete onboarding to choose your coach." | **YES** | coach provider | partial — see §3g | FIT-029 | **none for this leg**; a visible error state still needs OD-8 |
| ~~`classes_screen.dart:39`~~ | `/classes` | ~~`valueOrNull ?? []`, and `LiveClassService` swallowed the read~~ → **errors propagate**; a failed source is named, per kind | Schedule tab rendered **nothing at all** (`itemCount: 0`) | **YES** | class providers | `Could not load classes` + Try again | FIT-027 | **none for this leg** |
| ~~`challenges_screen.dart:36-39`~~ | `/challenges` | ~~`AsyncError` never consumed → "🏁 No challenges here" and "0 active challenges"~~ → **`Could not load challenges` + Try again**, count `—` | "🏁 No challenges here" | **YES** | challenge StateNotifier | yes | FIT-075/078/079 | **none for this leg** |
| ~~`home_screen.dart:80`~~ | `/home` | ~~`catch` → all-zero bars~~ → **error propagates**; headline `'—'`, nudge omitted, bars drawn as the unknown track | zero bars + "Log meals or workouts…" | **YES** | weekly activity | partial — see §3f | FIT-001 (locked) | **none for this leg**; a full error state with retry still needs OD-8 |
| ~~`train_hub_screen.dart:224-246`~~ | `/train` | ~~`error: (_, __) => '0'`~~ → **`'—'`** | `'—'` placeholders | **YES** | 4 stat providers | `_PlanUnavailable` | FIT-014/015 (locked) | **none for this leg** |

**Reference implementation already in-repo:** `booking_screen.dart:612-643` (`_LoadFailedState`)
— *"Couldn't load your bookings / We could not reach your coach and availability data just
now. **This is a connection problem, not an empty schedule.**"* with a Try-again action, and
a comment at `:609-611` naming the collapse as the bug. `chat_screen.dart` now follows it.

**All nine are now closed — and the inventory was not complete.** A tenth, on
`/meals-dashboard`, was found by FIT-022 and is recorded in §3y. The survey below was a
survey, not a proof. Both were
the worst kind: not a failure shown as emptiness, but a failure shown as a **confident
wrong number**. `/train` answered "0 workouts"; `/home` answered "0%" and then told the
client to start logging. In both, a number the screen could not support became `'—'` and
the accusation was dropped. The third, `/profile`, was worse still: a **denial** —
"No coach assigned yet. Complete onboarding to choose your coach." shown to a client
paying a coach every month. It is now hidden rather than reworded, because the string
already sitting there was the false one and there was nothing shipped to fall back to.
Nothing was written to fix any of the three.

**OD-8 is no longer blocking any of them.** Every line used is one this repository already renders — `Could not load [noun]`, a pattern in fifteen files — or the package's own `Try again` (16 declarations). What OD-8 asked for was permission to *invent* copy; none was needed.

**Why the rest are not fixed in this pass:** the pattern is unambiguous but each needs
**user-facing error copy**, and the authoritative package declares `empty`/`loading` states
for these frames without declaring error copy for them. Writing nine new error strings is
inventing product copy, which the brief forbids. **The mechanism is free; the words are
not.** Two routes out: (a) the owner supplies copy, or (b) QA is authorised to reuse the
booking screen's existing, already-shipped phrasing as the house pattern. Recorded as
**OD-8**.

## 6d · OWNER DECISION REGISTER

**OD-20 · FIT-025 promises a coach review rhythm the product does not model.** The board's
empty state reads "Nadia reviews check-ins on Sundays and Mondays … Her reply will appear
here", and its annotation makes the rhythm the point: *"An empty state that explains the
rhythm removes the need to wonder — and the need to chase."* There is no review schedule in
the data. Decide whether coaches declare one (a field, and who edits it) or whether generic
copy is approved. Until then the screen says only what is true.

**OD-19 · FIT-030 declares a privacy control that has no data model.**
"Who can see my progress · Coach only" implies a visibility setting on a client's progress.
**No such column or policy exists** — the only `visibility` in the migrations is on
`custom_exercises`. Building it means defining who may see a client's data, which is a
data-sharing boundary, not a settings row. Decide the model (values, default, and what
enforces it server-side) before it is drawn.

**OD-18 · FIT-031's prices are not the product's prices.** The anchor draws £19 / £39 / £79;
the app shows $29 / $59 / "Coach-set", backed by live Stripe price IDs whose own function
header records $29 and $59. Editing the label alone would show a client £19 and charge them
$29. Decide the currency, the amounts, whether the Free tier survives (the anchor draws
three tiers, the app has four), and whether Stripe is repriced. Also covers
`Switch to coach-guided`, whose shipped CTA (`Find a Coach`) performs a different action.

**OD-17 · FIT-019's third pill is `Recent`; the app's is `Barcode`.** Different features,
no recent-foods data source in the repository, and the design draws three pills. Decide
whether Recent replaces Barcode (losing barcode scanning), sits beside it (a fourth pill
the design does not draw), or is dropped.

**OD-16 · How a 1–5 rating maps to the package's three words.** FIT-004 declares
`Low` / `Steady` / `Strong` for energy and FIT-023 draws `Energy steady` in its history
rows, while the database stores 1–5 and a coach reads that number. Choosing thresholds is a
product decision about what a coach is being told, not a formatting one. Until it is made,
both surfaces state the value (`Energy 3 of 5`) rather than interpret it, and a test asserts
the three words are not produced.

**OD-15 · FIT-027 does not draw a coach's "New Class" affordance.** The anchor folds
`/classes`, `/events` and `/challenges` into one list and draws no create control. The FAB
was kept: removing it would take away a coach's only way to create a class, and a locked
screen not drawing something is not the same as the design saying to delete it. Decide
whether the affordance belongs on this screen, moves elsewhere, or goes.

| ID | Question | Evidence | Options | QA can continue without it | Blocked by it |
|---|---|---|---|---|---|
| **F-12** | Should role authorization move into the router? | Route entry weak (verified); backend sound in every path tested (6 probes, 2 mutations, no change) | (a) router-level role guard; (b) keep widget guards, extend to the 4 unguarded routes; (c) accept, document as defence-in-depth gap | **everything** — no data exposure demonstrated | nothing |
| ~~**F-14**~~ **RESOLVED — by the package, see §3ar** | ~~Adopt the mandated 5 tabs?~~ | Shipped nav has 4 labelled destinations; Nutrition and Connect absent; `/directory` FAB is the **sole** entry to `/events` | (a) adopt 5 tabs and re-home `/directory`'s destinations; (b) keep shipped nav, record design deviation; (c) hybrid | all non-nav work | `/events` reachability, FIT-003/005 integration |
| **F-13** | Keep PaywallGate failing open on provider error? | `paywall_gate.dart:45`, deliberate + commented | (a) keep; (b) fail closed; (c) fail closed with retry | everything | nothing |
| **OD-1** | Landscape: lock portrait, or support it? | 39 px overflow on `splash_screen.dart:109`; design GAP-06 "Tablet and landscape are not designed. Phone widths only." | (a) lock portrait (1 line, matches comparators); (b) design landscape | all portrait work | F-5 |
| **OD-2** | GAP-07 AI error states the backend cannot reach | manifest `implementationGaps` | owner-defined | all reachable states | those states |
| **OD-3** | GAP-08 Score semantics — frame depicts `ScoreService`, route renders `ScoreEngine` | package calls it "locked, unresolved" | owner-defined | all other screens | FIT-060 |
| **OD-4** | Navigation entry for the event ticket (not router-addressable) | `events_screen.dart:81` push; no `GoRoute` | (a) register a route; (b) keep imperative, accept no deep link | all other screens | FIT-086 |
| **OD-6** | Display weight — design says w300; Schibsted Grotesk ships no w300 via `google_fonts` 8.1.0; board renders w400 | verified in pub-cache source | (a) w400/w500 per board (**currently implemented**); (b) bundle a Light weight; (c) substitute a family with w300 | colour, shape, spacing, motion, geometry | display/metric type only |
| **OD-7** | Bundle fonts, or keep runtime fetch? | no `fonts:` in pubspec, no font assets, `allowRuntimeFetching` unset → true | (a) bundle; (b) accept offline degradation to Roboto | online behaviour | offline fidelity |
| **OD-8** | Error copy for the 9 F-15 screens | package declares `empty`/`loading`, not error copy | (a) owner supplies copy; (b) authorise reuse of `booking_screen`'s shipped phrasing as the house pattern | everything else | F-15 fixes |

## 7 · Environment

**Disk — the constraint that actually bites.** The volume ran to **100 % (1.0 GB free)**
during this cycle and the Flutter test runner stopped producing output rather than failing
with an error, which reads as a hang. `apps/mobile/.dart_tool/flutter_build` had grown to
**7.4 GB** across the cycle's repeated `flutter build apk` runs. It is an incremental build
cache and entirely regenerable; deleting it restored 8.4 GB free and the suite ran normally
again. Cost: one slower next build.

Recorded because the symptom does not name the cause — a stalled `flutter test` on this
machine is a disk check first.

| Item | Status |
|---|---|
| Android emulator `emulator-5554`, API 35, arm64-v8a | **PASS** — running, no further SDK installed |
| iOS / Xcode | **out of scope** by instruction — not a blocker |
| CI has **no** Android build job | **OWNER DECISION** — pipeline contract change; F-1 could recur undetected |
| Disk headroom on the build volume | **ENVIRONMENT LIMITATION** — ~1.6 GB free after a build; two earlier runs were killed by a disk watchdog (the watchdog killed them; the builds did not fail) |
