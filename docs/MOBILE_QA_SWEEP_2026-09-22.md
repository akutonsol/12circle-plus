# 12Circle Fitness Mobile — QA sweep, 2026-09-22

**Repository** `12circle-fitness` · **Branch** `chore/qa-environments-secure-ai-backend` ·
**Commit** `7c2266c0346f6da0e50eba16d5c58fa0a64f0e09` (in sync with `origin`, 0/0)

A full re-verification of the Mobile application's QA gates, run after migration 131
reached QA. This document records what was actually executed, with results. It does not
supersede `WAVE_3A_11_EXECUTION_EVIDENCE.md`, which remains the record for the migration
itself.

**Scope boundary, stated because a sibling workstream was live in the same session:**
this app is **Flutter/Dart**. It has no `@helix/design-system` dependency, no React
Native, no Metro, no npm design-system package — `grep -rn "@helix"` matches zero
JSON/YAML/JS/TS files repo-wide, and `apps/mobile/pubspec.yaml` declares no such
dependency. The `helix` under `apps/mobile/lib/core/helix/` is an **in-repo Dart token
system**, unrelated to the standalone `helix-design-system` package. The sole React
Native trace is a dead `"extraneous": true` entry in the root `package-lock.json`,
residue of an abandoned Expo scaffold with no backing `apps/mobile/package.json`.
Nothing from the Communities/Helix workstream applies here and nothing from it was acted
on.

---

## 1. Gates executed — all green

| Gate | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **0 errors, 0 warnings**, 160 infos |
| Flutter tests | `flutter test` | **819 passed**, 9 skipped |
| API unit | `npm test -w apps/api` | **58 passed** (8 suites) |
| API e2e | `npm run test:e2e -w apps/api` | **6 passed** (2 suites) |
| Production-ref guard | `.github/scripts/check-production-refs.sh` | OK |
| Migration hygiene | `.github/scripts/check-migration-hygiene.sh` | OK — 132 migrations, contiguous 000–131 |
| Edge-function config | `.github/scripts/check-edge-function-config.sh` | OK — 19 functions, `stripe-webhook` the only `verify_jwt=false` |
| I-MIG-03 durability | `migration-durability-guard.mjs` | **PASS (enforcing)** — 0 unrecorded regressions |
| ENV-3 static manifest | `check-migration-manifest.mjs` | OK (see §3 — static half only) |
| Schema contract | `npm run test:contract` | **PASS** — no unknown relation/column outside the 3-entry allowlist |
| QA web build | `flutter build web --dart-define-from-file=dart_defines/qa.json` | **Built** `build/web` |
| Web secret scan | `tool/check_web_build_secrets.sh build/web` | **PASS** — no server secrets, 85 files |
| Web ref allowlist | CI's inline scan | **PASS** — only `eyqtldjqpgpljlqvpowh.supabase.co` present |
| Live security suites | `npm run test:security` | **351/351 across 8 suites** |
| Live AI suites | `npm run test:ai` | **49/49 across 5 suites**, 17/17 characterizations still reproduce |

### Live security detail (QA project `eyqtldjqpgpljlqvpowh`)

D-01 43/43 · D-02 40/40 · D-03 27/27 · 1D 66/66 · 1E 75/75 · 1F 34/34 ·
**3A-10 chat-media 42/42** · **3A-11 identity constraints 24/24**.

Migration 131 re-confirmed live: frontier **131**, `131` ledger row present, **all seven**
objects present.

### Negative controls — 7/7 harnesses PASS

`wrk02` · `ec23` · `uix1` · `nut01` · `int02` · `icom01` · **`i3a11`** — each fails against
its pre-fix tree and passes post-fix, restoring byte-identically.

`supabase/scripts/negative-control.sh` is **ENVIRONMENT-BLOCKED locally** — `initdb` cannot
find a `postgres` binary beside it (the local install is `libpq` only, not a full server).
It is **not** claimed as passing on local evidence; it runs in CI, which supplies the
server.

---

## 2. Failures encountered and repaired

**DEPENDENCY_FAILURE — API suite could not run.** `npm run test:api` failed with
`jest: command not found`; `apps/api/node_modules` did not exist. Repaired with `npm ci`
(the command CI itself uses). No tracked file changed. The suite then passed 58 + 6.
Classification: harness/environment, **not** a product defect.

---

## 3. ENV-3 — declared vs observed divergence (UNRESOLVED)

| | |
|---|---|
| Live QA frontier | **131** (ledger row present, 7/7 objects) |
| `expected_applied.json` declares | `applied_through: "130"`, `pending: {"131": …}` |

`check-migration-manifest.mjs` passes — but only because its own output says *"This is the
STATIC half only: nothing here has looked at a real ledger."*

**The live half DOES exist and DOES catch this.** `supabase/scripts/live-evidence.sh` runs
in CI's `live-qa` job, `QA_DB_URL` **is** provisioned, and CI run `35794428054` reports:

```
PASS L-1  expected migrations missing from the ledger: 0
FAIL L-2  applied but undeclared: 1 — 131
PASS L-3  stale ledger rows (no authored migration): 0
PASS L-4  holes in the applied sequence (000-131): 0
FAIL L-5  ledger rows 132 vs declared expected 131
INFO      authored and PENDING for qa (declared, not applied): 131
          assertions: 3 PASS · 2 FAIL
```

*(Correction of record: an earlier draft of this section asserted the live half was never
implemented and the divergence was invisible to CI. That was wrong, and it was wrong
because it trusted `expected_applied.json`'s own header — "The live half of this contract
… is NOT implemented" — which is stale. CI evidence supersedes it.)*

L-2 and L-5 are the **same two assertions** that commit `de20ea7` recorded moving from FAIL
to PASS when the 130 frontier was reconciled. They now fail again, for 131, for the
identical reason.

Under ENV-3's own rule — *"a version applied without being declared here fails"* — the
declaration is factually behind reality. Reconciling it was explicitly excluded from the
migration-131 authorization and `WAVE_3A_11_EXECUTION_EVIDENCE.md` §14.7 records that it
requires its own authorization. **It remains unreconciled. No file was modified here.**

---

## 4. Design-system conformance — measured, unresolved

`apps/mobile/lib/core/helix/helix_semantics.dart:5-7` states the contract:
*"Components consume ONLY these — never raw hex."*

Measured against the tree:

| Metric | Measured |
|---|---|
| Presentation files under `lib/features/**/presentation/**` | 158 |
| Files reading `context.helix` / `HelixSemantics` | **0** |
| Files importing anything from `core/helix/` | **0** |
| Files with ≥1 non-semantic colour reference | **150 / 158 (94.9%)** |
| Total non-semantic colour references | **3,009** |
| Distinct `Color(0xFF……)` literals in presentation | **252** |
| Files declaring their own private palette class | **20** |
| Design/theme guard test | **none exists** |

Three competing palettes ship concurrently — the Helix brand tier, a legacy `AppColors`
(imported by 52 files though `AppTheme.darkTheme` is never installed), and 20 per-screen
private palettes. Four different brand purples are live at once (`0xFF7C5CFF`,
`0xFF7C3AED`, `0xFFA855F7`, `0xFFB76DFF`), and three background blacks.

Helix is instantiated once in `main.dart` and read by **zero** widgets.

**Not remediated.** Migrating 3,009 references is a design decision and a large refactor,
outside QA-repair scope. Two widget tests additionally hard-assert a hex that is not the
Helix accent (`test/widget/filter_chip_test.dart:90`), so any token migration must
reconcile those tests deliberately rather than incidentally.

---

## 5. Accessibility — measured, unresolved

| Metric | Measured across `lib/` |
|---|---|
| `Semantics(` widgets | **0** |
| `semanticLabel:` | **0** |
| `IconButton`s with neither tooltip nor semantic label | **49 / 49** |
| `GestureDetector` / `InkWell` without semantics | 392 / 7 |
| Hit boxes measurably below 44 pt | **38** |
| Explicit opt-outs of Material's 48 pt minimum (`tapTargetSize: shrinkWrap`) | **8** |
| Tests asserting any accessibility property | **0** |

Smallest hit boxes found include `action_center_screen.dart:191` (32×32),
`meals_dashboard_screen.dart:1146` (32×32), `nutrition_screen.dart:163` (28×36), and two
custom toggles at 48×26. Because these are raw `GestureDetector` + `Container`, Flutter
applies no minimum tap padding — the painted box *is* the hit box.

Two specific defects worth separating from the aggregate:

- `resume_workout_banner.dart:94-97` — an `IconButton` whose
  `padding: EdgeInsets.zero, constraints: const BoxConstraints()` strips its default
  48×48 minimum, leaving an unlabelled control about the size of its 18 px icon.
- `train_hub_screen.dart:701,705` — `_IconBtn` declares a `tooltip` parameter that its
  `build` never uses. The string is accepted and silently discarded, reaching neither a
  `Tooltip` nor the semantics tree. Three call sites pass it believing it does something.

**Not remediated.** Labels are product copy and target sizes change layout; both are owner
decisions, not QA repairs.

---

## 6. Mutation made

**`.github/workflows/ci.yml`** — one step added (+12 lines, 0 deletions, purely additive):

```yaml
- name: 3A-11 — identity constraint guards, pre-fix / post-fix evidence
  run: apps/mobile/tool/negative_control/i3a11_negative_control.sh
```

`i3a11_negative_control.sh` has existed since 3A-11 and passes, but was the **only one of
the seven** negative controls CI never executed — its six siblings are all wired. It needs
no credential, no network and no new job, reusing the Flutter set-up and `fetch-depth: 0`
checkout already present in that job. YAML re-validated after the edit.

**Uncommitted.** No push authorization was given for this repository.

---

## 7. CI

A `workflow_dispatch` run was triggered at this commit (run `35794428054`) because CI had
**never run green here** — the previous run at this same SHA (`34410026228`, 2026-09-09)
failed on `d08`, which could not pass before migration 131 was applied. That run predates
the application and its failure is no longer representative.

Note the triggered run executes the **committed** `ci.yml`, so it does not include the §6
step.

### Result — `35794428054`

| Job | Conclusion |
|---|---|
| Static guards | **success** |
| API — unit + e2e | **success** |
| Flutter — analyze, test, QA web build | **success** |
| Negative control | **success** |
| Live QA suites (security / AI / contract) | **failure** |
| UIX-1 booking e2e | skipped |
| I-WRK-01 live progression | skipped |

Inside the failing job, steps 1–9 all succeeded — including **Live security suite** and
**Live AI suite**, independently corroborating the local 351/351 and 49/49 above. The
**only** failing step is step 10, *Live SQL evidence — FG-1, FG-2, ENV-3 ledger*, and
within it only the two ENV-3 assertions in §3. FG-1 5/5, FG-2a 20/20, FG-2b 15/15 pass.

Two consequences worth separating:

1. The whole CI run is red for **one** reason: the §3 declaration divergence.
2. `uix1-e2e` and `wrk01-live` are gated on `live-qa` and therefore **skipped**. Those two
   gates have still never executed at this commit, and reconciling §3 is what unblocks
   them.

---

## 8. Not verified — stated rather than implied

- **No iOS or Android runtime testing** — see §10, which supersedes an earlier draft of
  this line that claimed no runtime testing at all. The **web** surface was subsequently
  run and rendered; iOS and Android remain untested and are environmentally unavailable.
- **AI features are not verified end-to-end.** The AI suite passes as a *characterization*
  suite and records that **no AI edge function is deployed** (7/7 `NOT_FOUND`, F-J-15).
  Green here means the characterization still holds, not that AI works.
- **Stripe** — no QA test-mode credentials (EB-5); `I-PAY-01` terminal closure stays
  deferred to Wave 6 / K-01. The database arbiter is proven; the webhook replay is not.
- **Edge Function tests** — 19 tests unrunnable, no Deno runtime (EB-8).
- **`live-evidence.sh`** — needs a `QA_DB_URL` database credential that does not exist
  here; FG-1, FG-2 and the ENV-3 live comparison remain uncollected.
- **Gate 6 manual QA matrix** (22 surfaces × 10 conditions) — never prepared or executed
  (EB-9: no UI harness, no device).
- **Production** — not contacted. Production `schema_migrations` has still never been
  dumped or reconciled (Gate 9B.2 / G-09).

---

## 9. Governance documents are stale

`REMEDIATION_PROGRESS.md` is stamped 2026-08-28 and still shows Wave 1 IN PROGRESS with
Waves 2/3A/3B blocked; `MASTER_REMEDIATION_REGISTRY.md`'s last reconciliation is §7.22
(2026-08-31). Neither records the 3A-9 / 3A-10 / 3A-11 outcomes, all three of which have
since landed and been applied to QA. `WAVE_3A_11_EXECUTION_EVIDENCE.md`'s own header still
reads "NOT COMMITTED, NOT APPLIED", contradicted by its own §14.

Updating those boards is ARCH-owned and was not done here.

---

## 10. Runtime verification — web surface (second pass)

*This section supersedes the earlier "no runtime testing" line in §8, which was written
before runtime availability had actually been established rather than assumed.*

### Availability, measured

| Target | State | Evidence |
|---|---|---|
| iOS simulator | **UNAVAILABLE** | `/Applications/Xcode.app` does not exist; only CommandLineTools. `xcrun simctl list devices available` returns no iPhone/iPad. `flutter doctor`: *"Xcode installation is incomplete"*, CocoaPods absent |
| Android emulator | **UNAVAILABLE** | `flutter doctor`: *"Unable to locate Android SDK"*; no `adb`, no emulator binary |
| macOS desktop | listed by `flutter devices`, but unbuildable without Xcode |
| **Chrome (web)** | **AVAILABLE** | `flutter devices` lists Chrome 153; web is a first-class target here (CI builds it; the tree carries web-only sources) |

Neither mobile platform is fixable from inside QA — installing Xcode or the Android SDK is
a multi-gigabyte owner action.

### What was actually run

The `build/web` artifact produced in §1 was served on `127.0.0.1:8799` and loaded in a real
browser, then rendered in headless Chrome for pixel evidence.

**Verified:**

- The app **boots**: `flutter_bootstrap.js` and `main.dart.js` 200, engine initialises
  (`_flutter` defined), `flutter-view` and the glass pane mount.
- **Zero console errors** and **zero failed network requests** across the session.
- All assets resolve 200 — fonts, splash imagery, brand marks.
- **`go_router` works at runtime**: `initialLocation` lands on `#/splash`, and a hash route
  to `#/login` resolves.
- **Two routes render complete, correct UI.** The onboarding/splash screen paints its brand
  ring, hero image, eyebrow, display headline, body copy, primary CTA and secondary
  "Sign In" affordance. `/login` paints "Welcome Back", email and password fields, a forgot
  link, the Sign In CTA, an OR divider, Google and Apple provider buttons, and the Sign Up
  link.
- **No backend egress before authentication** — no Supabase request is issued at rest, and
  no non-QA host was contacted at any point.

**A clipping artifact was observed and is NOT a product defect.** Content appeared cut at
the right edge in headless captures. Cause, measured: `flutter-view` reported
`width: 500px; height: 809px` inside a `414×896` window — *neither* dimension matches, so
headless Flutter was not reading the real viewport. A genuine minimum-width would have
matched the window height. Classified **ENVIRONMENT/HARNESS**. The same limitation appears
in the hosted browser pane, where a hidden pane leaves the view at 0×0 and Flutter never
composites.

**Consequently still unverified at runtime:** responsive layout at specific device widths
(no true 414 px logical viewport was achieved), all interaction, and every authenticated
flow. No credentials were entered.

---

## 11. Second-pass repairs

### 11.1 Product defect repaired — dead `tooltip` parameter

`lib/features/workout/presentation/train_hub_screen.dart` · `_IconBtn`

`_IconBtn` declared `final String tooltip` as a **required** parameter and its `build`
returned a bare `GestureDetector`. The string reached neither a `Tooltip` nor the semantics
tree. Two call sites pass `'History'` and `'Exercise Library'` believing they label the
control; a screen reader announced nothing.

A required parameter that is never read is unambiguously an implementation defect rather
than a design choice, which is why this was repaired while the broader labelling question
in §5 was not. The fix wraps the existing widget in `Tooltip(message: tooltip, …)` —
`Tooltip` carries its message into semantics, so **two previously unlabelled controls are
now labelled using copy that already existed**. No product copy was invented.

The 40×40 hit box remains below 44 pt. That is a layout change and stays an owner decision.

### 11.2 QA guard added — `test/unit/presentation_drift_guard_test.dart`

Three assertions, in the shape the suite's other guards already use:

- **A-G1** — no presentation widget may declare a `tooltip` field it never reads (the
  defect class above), plus a specific assertion that `_IconBtn` carries its tooltip.
- **H-D1** — a **drift ratchet**, not a conformance guard: the 20 files that declare a
  private colour palette are pinned by name, and the test fails on the 21st. It does not
  judge the existing 20. This is the "safe QA-only guard" the design-system question
  permits: it holds the line while D-2 is outstanding, without pre-empting the decision or
  requiring a 3,009-reference migration.

**Both were mutation-tested**, to this repository's own §2 standard. Reverting `_IconBtn`
to its bare-`GestureDetector` form makes A-G1 fail; restoring makes it pass, byte-exactly.

That mutation test earned its keep: the **first** version of A-G1's general scan returned a
false negative, because its "consumed" pattern matched `required this.tooltip` in the
constructor — which is a declaration, not a consumption. The guard was tightened to strip
constructor initialisers before checking, and re-mutated: both assertions now fail pre-fix
and pass post-fix. Recorded because a guard that has never failed proves nothing.

### 11.3 Regression after the change

`flutter analyze` **0 errors, 0 warnings** (175 infos, unchanged). Full suite **822 passed**
(819 + the 3 new guards), 9 skipped. `ec23` and `i3a11` negative controls re-run and still
PASS, restoring the tree byte-identically.

---

## 12. Runtime verification — web, third pass (clipping resolved, routes exercised)

Instrument: headless Chrome 153 driven over the Chrome DevTools Protocol from a
dependency-free Node 22 script (native `WebSocket`; nothing installed). CDP is used
because `Emulation.setDeviceMetricsOverride` sets the **layout viewport** independently of
the OS window — the distinction the previous pass could not make.

### 12.1 The splash-copy clipping — RESOLVED: capture artifact, not a defect

§10 classified the clipping as a harness artifact from a single measurement. That was the
right call but under-evidenced. Measured properly:

| `--window-size` | resulting `flutter-view` |
|---|---|
| 320×900 | **500**×813 |
| 390×900 | **500**×813 |
| 430×900 | **500**×813 |
| 768×900 | 768×813 |
| 1440×900 | 1440×813 |

`flutter-view` tracks the window exactly at 768 and 1440 but **floors at 500** below it.
Two candidates remained — an app min-width (a real defect) or Chrome's own minimum window
width — and `--window-size` cannot separate them, because Chrome will not create a window
narrower than ~500 px.

With a true viewport override the ambiguity disappears:

| viewport | `window.innerWidth` | `flutter-view` | `document.scrollWidth` | overflow |
|---|---|---|---|---|
| 320 | 320 | **320**×900 | 320 | none |
| 390 | 390 | **390**×900 | 390 | none |
| 430 | 430 | **430**×900 | 430 | none |
| 768 | 768 | 768×900 | 768 | none |
| 1024 | 1024 | 1024×900 | 1024 | none |
| 1440 | 1440 | 1440×900 | 1440 | none |

`flutter-view` tracks the viewport exactly at every width, and `scrollWidth == innerWidth`
at every width — **zero horizontal overflow anywhere in 320–1440**. The 500 px floor was
Chrome's minimum window width and never an app constraint.

**Classification: B — viewport/capture artifact.** Confirmed visually: at 320 px the splash
body copy renders complete ("…built to push you through all 12 weeks."), the headline wraps
to two lines, and the CTA is correctly inset. The login screen at 390×844 likewise renders
whole — "Forgot password?", both provider buttons, and the footer link all intact.

*The responsive-behaviour item listed as unverified in §10 is therefore now VERIFIED at six
widths, and this supersedes that line.*

### 12.2 Route sweep — 16 routes at 390×844

Each route was loaded from a clean page load; renders are compared by SHA-256 of the
screenshot, not by byte length alone.

- **Public routes render distinctly**: `/onboarding` (205,249 B), `/login` (93,284 B),
  `/signup` (111,667 B), `/forgot-password` (89,137 B) — four different screens.
- **Auth guard VERIFIED LIVE.** `/home`, `/workouts`, `/progress`, `/nutrition`,
  `/messages`, `/settings`, `/profile`, `/train`, `/community` — all nine are
  **pixel-identical** to `/login` (`3b60b908…`). Unauthenticated access to a protected
  route lands on sign-in.
- **REL-3 VERIFIED LIVE.** `/qa-center` and `/mie-debugger` are also pixel-identical to
  `/login`. `flutter build web` is a release build, so `kQaToolingEnabled` is false and the
  debug routes are not registered. This is the runtime counterpart of the static assertion
  in `release_route_gate_test.dart`.
- **Unknown route degrades gracefully** — `/this-route-does-not-exist` lands on sign-in. No
  crash, no blank screen, no unhandled exception.
- Across all 16: **0 console errors, 0 failed network requests, 0 horizontal overflow.**

### 12.3 Interaction — verified

- **Password visibility toggle works.** Clicking the eye control on `/login` changes the
  render (93,284 B → 93,400 B).
- **Navigation by real user input works.** Clicking "Sign Up" drives the route to
  `#/signup`, and the resulting render is **111,667 B — exactly the `/signup` fingerprint**
  from the sweep above. Input, routing and rendering are consistent end to end.

### 12.4 Authenticated UI runtime — BLOCKED (harness), not a product finding

A QA fixture session was minted through the auth API — the same path
`supabase/tests/security/lib.mjs` uses — and injected into `localStorage` so the UI could be
driven authenticated **without typing credentials into a form**. Three key/format
combinations were tried (`flutter.supabase.auth` and `supabase.auth`, wrapped and raw);
the compiled bundle's own key strings (`"supabase.auth"`,
`"supabase.auth.token-code-verifier"`) were read to inform them. The app did not restore
the session and continued to route to `/login`.

Classification **HARNESS_FAILURE**. It is not evidence of a product defect: the injection
simply does not reproduce `supabase_flutter`'s exact persistence format, and PKCE
code-verifier state is likely also required.

What this leaves genuinely unverified is **authenticated UI rendering on web**. Authenticated
*authorization* behaviour is not unverified — the live suites in §1 sign in as these exact
fixtures and exercise RLS, RPC execution and authorization boundaries across 351 assertions.

The remaining route to authenticated UI would be typing the fixture password into the login
form. That was deliberately not done.

---

## 13. D-1 / ENV-3 — governance investigation, and why it was NOT reconciled

A forensic read of every governing text was performed specifically to answer: does this
repository's own governance record **explicitly authorize** changing
`qa.applied_through` 130 → 131 and clearing `pending`, now that 131 is applied and verified?

**Finding: no document states a general rule either way.** There is no migration-application
checklist anywhere in `docs/` that contains the step at all. Every governing text is
instance-specific — about 128, or 130, or 131, never about the class.

**Evidence that it is a procedural consequence (would authorize):**
- `expected_applied.json:11-12` — *"The frontier can only move when reality and intent move
  together."* Both have now moved.
- The 131 `gate` field names exactly one releasing condition — application under separate
  explicit authorization — and that condition **has fired**.
- `fb36f18` — *"This commit reconciles the declaration to the state that application
  produced"* … *"The declaration is moved AFTER the application, never before it."*
- `docs/decisions/DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md:737` — *"`expected_applied.json`
  **must** move `applied_through` to 130 — the `352ee68` precedent."*
- None of the four precedent commits (`c66f575`→124, `fb36f18`→128, `352ee68`→129,
  `de20ea7`→130) cites an owner ruling for the frontier move itself.

**Evidence that it requires a discrete owner act (withholds authorization):**
- `WAVE_3A_11_EXECUTION_EVIDENCE.md:609-610` — the most recent and most on-point sentence in
  the repository: *"Reconciling `applied_through` to `131` and clearing `pending` **requires
  its own separate authorization**."*
- `WAVE_3A_11_READINESS_AUDIT.md:404-406` — *"**Never, at any step:** … editing
  `expected_applied.json` for any reason but steps 1 and 3"*. No enumerated step covers a
  131 frontier move. The default posture toward this file is prohibition-with-exceptions.
- `WAVE_3A_11_RULING_VALIDATION.md:232` — *"Separate authorization? **Yes, for both.**"*
- Four consecutive application authorizations each explicitly carved this file out of scope.

**Verdict: explicit authorization is ABSENT.** Ambiguity pointing both ways is not explicit
authorization, and authorization may not be inferred from the change being obviously
correct. **`supabase/expected_applied.json` was NOT modified.**

**One asymmetry the owner should know, because it makes the decision cheap:** no text
anywhere grants anyone discretion to *decline* this reconciliation. Every text treats the
post-application declaration as a state the file *should* reach. What is disputed is **who
may perform the edit under which grant**, not whether the end state is correct. This reads
as a procedural-authorization requirement rather than a substantive re-decision — but the
repository never says so, and that gap was not filled here.

**Status: OWNER-AUTHORIZED GOVERNANCE BLOCKER.** It remains the sole cause of CI red, and it
keeps `uix1-e2e` and `wrk01-live` skipped.

---

## 14. Accessibility — runtime semantics tree (corrects §5)

§5 counted source: 0 `Semantics` widgets, 0 `semanticLabel`, "49/49 `IconButton`s
unlabelled". Static counting was the wrong instrument, and the figure overstated the
problem. Flutter builds a semantics tree automatically from `Text` descendants, so a
control with a text child **is** announced without any `semanticLabel` in source.

Measured at runtime by activating Flutter's own `flt-semantics-placeholder`
("Enable accessibility") and reading the resulting `flt-semantics` tree — i.e. what a screen
reader actually consumes. On `/login`: 17 nodes, 13 carrying role/label/text.

**Text-bearing controls ARE labelled.** "Forgot password?", "Sign In", "Apple",
"Don't have an account? Sign Up" all expose accessible names from their child text.
"Google" announces as "G Google" — awkward, not inaccessible.

**The genuine defect class is icon-only controls**, and it is small and specific:

| Route | buttons | unlabelled | size |
|---|---|---|---|
| `/onboarding` | 2 | **1** | 56×56 |
| `/login` | 6 | **1** | **20×20** |
| `/signup` | 9 | **1** | **20×20** |
| `/forgot-password` | 3 | **1** | **22×22** |

**DEFECT (P3), evidence-backed:** the password-visibility toggle on `/login`, `/signup` and
`/forgot-password` is an icon-only control that announces only as "button" with no name, at
**20×20 / 22×22** — less than half the 44 pt minimum on both axes. It is simultaneously
unlabelled and undersized, and it is a control users must operate to check a password they
typed.

**Not fixed, deliberately.** Labelling it requires copy ("Show password" / "Hide password");
`grep` confirms no such string exists anywhere in `lib/` to reuse, so supplying one would be
inventing product copy. Resizing it changes layout. Both are owner calls. This is now a
**single, precisely located fix** rather than the vague "49 controls" of §5.

Also measured: several text links sit at 20–22 px height (`"Forgot password?"` 122×20,
`"Don't have an account? Sign Up"` 219×20, `"I agree to the Te…"` 342×22). Below the 44 pt
guideline on the vertical axis. Recorded as **OBSERVATION** — inline text links are a
widespread convention and calling them defects would be a product judgement.

---

## 15. Network-failure and offline runtime

Driven over CDP against the served QA build.

| Scenario | Result |
|---|---|
| Supabase host blocked (`Network.setBlockedURLs`) | App boots and renders `/login` identically to healthy (93,284 B). **0 JS errors, 0 unhandled exceptions.** |
| Fully offline (`emulateNetworkConditions offline:true`) | `readyState=complete`, 0 errors |
| Network restored | `/login` renders normally — clean recovery |

**Honest limitation, stated rather than glossed:** `netFails` was **0** in the blocked
scenario — because the unauthenticated surface issues **no backend request at all** (already
established in §10). Blocking the host therefore never exercised an error path. This
evidences **graceful boot and render without a backend**; it does **not** evidence
backend-error-state handling. That would require an authenticated session, which is
BLOCKED per §12.4.

Error-contract coverage does exist statically and passes: `ui_error_surface_guard_test.dart`
(EC-G6…G8) and `error_contract_guard_test.dart` are green in the 822-test suite.

---

## 16. D-1 / ENV-3 — AUTHORIZED AND RECONCILED

**Authorization.** The owner explicitly authorized the two-line reconciliation, scoped to
`supabase/expected_applied.json` only, with migrations, schema, production, CI logic,
application code, other declarations, and commit/push all excluded. This supersedes §13's
"authorization absent" verdict — the missing grant was supplied.

### 16.1 Pre-change state, re-confirmed

Live QA: frontier **131**, `131` ledger row present, **`132` ABSENT**, 132 ledger rows.
Declaration: `applied_through: "130"`, `pending: ["131"]`, `excluded: []`.

### 16.2 The change — exactly two fields

```diff
-      "applied_through": "130",
+      "applied_through": "131",
       "excluded": [],
-      "pending": {
-        "131": { "reason": …, "gate": … }
-      }
+      "pending": {}
```

`+2 / −7`, one file. `ref`, `name`, `excluded`, and the entire `_` header block are
untouched. This is the same shape as the `fb36f18` precedent (frontier bumped, pending
cleared).

### 16.3 Validation

- **JSON valid**; parses to `applied_through: 131`, `pending: {}`, `excluded: []`.
- **ENV-3 static** (`check-migration-manifest.mjs`): **OK** — *"frontier 131 (expected
  applied: 132 version(s), 000–131) · authored, PENDING (none) — the tree and this
  environment's frontier agree."*
- **ENV-3 LIVE** — CI's own generator (`supabase/scripts/env3-live-check.mjs --env qa`)
  executed against the live QA ledger:

```
=== ENV-3 LEDGER (qa) ===
PASS L-1  expected migrations missing from the ledger: 0 — —
PASS L-2  applied but undeclared: 0 — —
PASS L-3  stale ledger rows (no authored migration): 0 — —
PASS L-4  holes in the applied sequence (000-131): 0 — —
PASS L-5  ledger rows 132 vs declared expected 132
INFO authored and PENDING for qa (declared, not applied): (none)
```

**L-2: FAIL → PASS. L-5: FAIL → PASS.** L-1/L-3/L-4 unchanged at PASS. The two assertions
that `de20ea7` recorded flipping green for 130 have now flipped green for 131, for the
identical reason. (The surrounding `P0001` is the script's own `RAISE`-to-roll-back
reporting path, which `run_suite` consumes — not an error.)

- **Ledger unchanged by the edit**, as a declaration-only change must be: frontier still
  **131**, `132` still **ABSENT**, 132 rows, all **7** migration-131 objects present.
- **No migration file touched**; `git status supabase/migrations/` clean.

### 16.4 CI — why the job is not re-run here

The edit is **uncommitted**, and commit/push were explicitly excluded from this
authorization. CI builds the committed tree, so triggering a run now would execute the
*old* declaration and reproduce the identical `L-2`/`L-5` failure — an expensive run with
unchanged inputs and misleading output. It was therefore not triggered.

The evidence above is not a substitute of lesser kind: it is **CI's own generator against
the same live database**. What remains un-exercised is the CI *job*, not the assertion.

### 16.5 Downstream jobs — still NOT_RUN

`uix1-e2e` and `wrk01-live` are `needs: [live-qa]`, so they stay skipped until `live-qa`
passes **in CI**, which requires the commit. They also cannot be run locally: both default
to `PROBE_DEVICE=linux`, and the only devices here are `macos` (needs Xcode — not
installed) and `chrome` (needs chromedriver — not installed). Installing either is a
system-level toolchain change outside QA authority.

**Status: NOT_RUN — blocked on commit authorization, and environment-blocked locally.**

---

## 17. D-4 authorized — committed, pushed, CI fully green

Recorded retrospectively, following the `1b2fe57` precedent: a run's result cannot be
named by the commit that causes it.

### 17.1 Commits

| | |
|---|---|
| `ea1c6dd` | `chore(ENV-3): reconcile QA migration frontier to 131` — **one file**, `supabase/expected_applied.json`, +2/−7 |
| `55ae5f0` | `test(QA): wire the dormant 3A-11 negative control, fix a dead tooltip, add drift guards` — 4 files, +831/−9 |

Split along the repository's own precedent (`352ee68` / `fb36f18` / `de20ea7`): a frontier
move after application is its own commit. Pushed to
`origin/chore/qa-environments-secure-ai-backend`; remote HEAD `55ae5f01`.

Deliberately **not** included: `docs/WAVE_3A_11_EXECUTION_EVIDENCE.md` and the three
untracked audit documents, per the authorization's file list.

### 17.2 CI run `35799461932` — ALL SEVEN JOBS SUCCESS

| Job | Result |
|---|---|
| Static guards | **success** |
| API — unit + e2e | **success** |
| Flutter — analyze, test, QA web build | **success** |
| Negative control | **success** |
| Live QA suites (security / AI / contract) | **success** |
| **I-WRK-01 — live progression read path** | **success** ← never executed before |
| **UIX-1 — booking surface end-to-end** | **success** ← never executed before |

This is the **first fully green run this branch has ever produced.**

### 17.3 ENV-3, confirmed in CI

`live-qa` step 10, *"Live SQL evidence — FG-1, FG-2, ENV-3 ledger"* — **success**. That is
the exact step that failed in run `35794428054` with `L-2`/`L-5`. CI independently
confirms §16.3's local result.

### 17.4 The newly-wired negative control, confirmed in CI

`negative-control` step 12, *"3A-11 — identity constraint guards, pre-fix / post-fix
evidence"* — **success**. All seven harnesses now execute in CI: `M-1/2/3`, `WKT-204`,
`EC-23`, `UIX-1`, `I-NUT-01`, `I-INT-02`, `I-COM-01`, `3A-11`.

### 17.5 The two first-ever jobs — results verified, not assumed

Job conclusions were not taken as evidence; the step output was read.

**I-WRK-01** — `🎉 3 tests passed` · `RESULT: PASS — I-WRK-01 VERIFIED LIVE legs both
established.` The `❌ pre-fix leg … (failed)` line in the log is the **required** pre-fix
failure of a negative control, followed by `✅` on the restored tree. Fixture hygiene:
`WRK01-MARK CLEANUP verified remaining=0`, and CI's own independent re-check
`fixture WRK01-PROBE-35799461932-1 — rows remaining after cleanup: 0`.

**UIX-1** — `UIX1-MARK ASSERT-ALL PASS` · `🎉 2 tests passed` · `RESULT: PASS` ·
**`Evidence class: UIX-1 VERIFIED END-TO-END — real route, real PaywallGate, real
surface`**. The booking surface was reached through the real `/appointments` route, passed
the real paywall, and rendered the real coach. Fixture retirement proven:
`run-tagged availability remaining: 0 ; active relationships remaining: 0`.

**Carried forward honestly — UIX-1's own self-declared gap:**
> `NOT ESTABLISHED: the failure path (A4). See the probe header — _load() returns at
> uid == null before its try/catch, so _LoadFailedState cannot [be reached]`

The harness says one path is not established. That is **not** a green result for A4 and is
not counted as one.

**No fixture leaked in either job** — the failure mode that blocked migration 131 in §13
did not recur.

---

## 18. Post-green closure sweep

Run against `6cc1ff6a`, CI `35799894916` (7/7 success). Nothing below re-runs completed
work; each item adds coverage or examines a state that could have changed.

### 18.1 CI forensics — three caveats a "passed" summary would have hidden

**(a) The security roll-up is 350/350 here, not the 351/351 recorded in §1.** The difference
is one *conditional* assertion, not a regression. `d02-role-escalation.mjs:137-144`:

```js
if (pub.status === 429) {
  console.log('  SKIP  public /auth/v1/signup — project email rate limit (429); …');
} else {
  check('public signup cannot mint an admin', …);
}
```

CI logged that SKIP. Re-running `d02` locally now reproduces it — **39/39, still rate-limited**.
So the suite's count is **non-deterministic (39 or 40 for D-02, 350 or 351 overall)**
depending on Supabase's email rate limiter. Both figures were correct for their moment;
§1's "351/351" should be read as 350–351. The underlying invariant is not uncovered — the
harness notes *"the same handle_new_user() trigger is covered above."*
Classification: **ENVIRONMENT_BLOCKED (intermittent)**.

**(b) Two `##[error] N tests passed, M failed` lines appear inside green jobs.** These are
the negative controls' **required** pre-fix legs — e.g. `❌ WKT-204 … (failed)` immediately
followed by `✅` and `restore: committed implementation`. Working as designed.

**(c) Skip inventory, complete:** 9 Flutter skips, all
`billing_entitlement_contract_test.dart` K/OPEN executable specifications (K-01…K-12,
K-ENV-1) for findings that remain open on Stripe test mode (EB-5) · 1 AI section, J-03E
writes · 1 security assertion, (a) above.

**J-03E was deliberately NOT run.** `j03-engine-boundary.mjs:89-101` gates it behind
`AI_ALLOW_WRITES=1`, and its own comment states **"decision_traces rows are not
client-deletable."** Running it would add one characterization assertion at the cost of
permanent uncleanable residue in shared QA — the exact failure mode that blocked migration
131 in §13. Not run, by choice.

### 18.2 Authenticated UI runtime — §12.4 SUPERSEDED

§12.4 recorded authenticated UI runtime as harness-blocked. That was true locally and is
now **superseded**: the sanctioned mechanism already exists and already passed.

`integration_test/uix1_booking_e2e_test.dart:121-132` signs in for real —
`_db.auth.signInWithPassword(email, password)` against the fixture identities, asserting
`currentUser != null` — then drives the real app. CI logged `UIX1-MARK AUTH ok
client-session=true`, `ROUTE navigated=/appointments`, `A1 surface-reached=true`,
`A2 coach-rendered=true`, `A3 ready-state=true`.

**Authenticated UI rendering is VERIFIED — in CI, on Linux desktop.** It remains
unavailable *locally* (no Xcode for macOS desktop, no chromedriver for web), which is an
environment limit, not a coverage gap.

### 18.3 UIX-1 A4 — NOT_ESTABLISHED, and it is a TEST limitation, not a product defect

A4 is not an oversight. The probe header says so verbatim
(`uix1_booking_e2e_test.dart:50-55`):

> `A4 IS NOT ASSERTED, AND THAT IS A RECORDED LIMITATION, NOT AN OVERSIGHT.`
> `_LoadFailedState` cannot be reached honestly from here: `_load()` returns at
> `uid == null` before its try/catch (booking_screen.dart:50), so an unreachable URL yields
> `noCoach`, not `error`. Reaching it would need a production-code edit, an RLS change, or a
> mock — all forbidden by the owner ruling.

**What A4 would assert:** the inverse of A3's third negative — that when the authoritative
read genuinely fails, the surface renders `_LoadFailedState` ("Couldn't load your bookings"
+ Try again) rather than the confident empty answer `_NoSlotsState`. That false success is
the exact defect this workstream exists to prevent.

**`_LoadFailedState` is NOT dead code** — three independent pieces of evidence:
1. `app_router.dart:180-198` redirects unauthenticated users to `/login`, and
   `/appointments` sits behind `PaywallGate`, so in production `uid` is non-null and the
   `try`/`catch` **is** the live path. The harness's blocker and production's behaviour are
   inverted.
2. The catch has demonstrably executed in production: PostgREST answered `PGRST200` for the
   `coach:coach_id(…)` embed, and `_load()`'s catch turned it into a confident "no slots" —
   the original M-03 defect. UIX-1 changed what that catch *renders*.
3. `_LoadFailedState(onRetry: _load)` plus the AppBar refresh shown in every state except
   `loading`/`noCoach` is an intended live re-entry after a transient outage.

**Structural cause — a testability defect, recorded not fixed:**
`booking_screen.dart:26` — `final _db = Supabase.instance.client;`. The screen reaches the
network through a global singleton inside a `StatefulWidget`, so there is **no seam to fail**.
Every error state in this repo that *is* tested sits behind a Riverpod provider — compare
`test/widget/active_workout_hydration_test.dart:21-59`, which does exactly the A4-shaped job
for another screen via `activeWorkoutRestorationProvider.overrideWith(...)`, with no backend
and no production access. A4 becomes trivially testable the moment that read moves behind a
provider. Moving it is a product change and was not made.

**One candidate path exists that touches neither production code, RLS, nor a mock:** reach
`ready`, break host reachability on the CI runner, then tap the AppBar refresh — `uid` stays
non-null from the cached session, the PostgREST call fails, and the catch renders
`_LoadFailedState`. This is *environment-level fault injection*. It is implemented nowhere
in the repo, and the owner ruling quoted in the header does not enumerate it in either
direction. **OWNER DECISION** — not assumed, not implemented.

### 18.4 Error / empty / loading coverage — measured

| Measure | Count |
|---|---|
| Presentation files | 158 |
| Using `.when(` | 39 — **all 39 declare both `error:` and `loading:`** |
| Bypassing `.when()` via `.valueOrNull` | **41** (collapses an error to `null` beneath any declared arm) |
| `error: → SizedBox/Container` swallows | **16** |
| Tests rendering loading/empty/error as distinct outcomes | **1** (`active_workout_hydration_test.dart`, WKT-112) |

Branch *presence* is 100%; the real hole is `.valueOrNull`. All three ratchets are green and
already pin these: EC-G7 at baseline **16**, EC-G8 at **134**, EC-G5 at **234**, each checked
bidirectionally so a fix must lower the baseline.

Two findings worth recording:
- **A sanctioned-swallow list exists, but only for the service layer.**
  `docs/QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md` §5 enumerates exactly five allowed cases.
  There is **no presentation-layer equivalent**, so all 16 `error: → SizedBox` branches are
  unsanctioned by contract and held only by EC-G7's numeric ratchet. **OWNER DECISION**
  whether to sanction or remediate them.
- **`EC-G6` deliberately pins a live defect by name** —
  *"DEFECT: Train hub renders the failure as 'nothing to resume'"* — with the instruction to
  delete the test when the arm gains a retry. It is a defect marker, not a passing contract.

### 18.5 Accessibility — the label question is settled as a product decision

`semanticLabel` appears in **0 files** across `lib/`; `tooltip:` in **3** (one of which is
`'Filter'`; the other two are the `_IconBtn` strings §11.1 wired). There is **no established
accessibility-label convention and no reusable copy** anywhere in the repository. Labelling
the password-visibility toggle therefore requires inventing product copy, which QA will not
do. **OWNER DECISION**, unchanged from §14.

### 18.6 Security regression — scoped, not repeated

The three commits touched `ci.yml`, `train_hub_screen.dart`, a new test, the evidence doc,
and `expected_applied.json`. **No migration, Edge Function, auth, policy, `app_env`,
`config.toml` or `dart_defines` file was touched**, so nothing could invalidate the security
evidence — and that evidence is current regardless: the full live suite ran **in CI at
`6cc1ff6a`**. Prod-ref guard re-run on the current tree: OK, both arms.

### 18.7 Fixtures

Independently re-verified after all CI activity: conversations **1** (the pre-existing
25-message survivor), duplicate participant pairs **0**, payments **0**, session credits
**0**, p1-victim cycle logs **0**. Both CI probes proved their own removal
(`UIX1-MARK CLEANUP verified availability=0 active-relationships=0`;
`WRK01-MARK CLEANUP verified remaining=0`, plus CI's independent re-check). **No fixture
leaked, by me or by CI.**

---

## 19. Android runtime gate — pursued to a hard, quantified blocker

§10 recorded Android as unavailable on the strength of `flutter doctor` alone. That was
under-investigated. This section supersedes it with an actual attempt.

### 19.1 No sanctioned tooling existed to reuse

Searched exhaustively before building anything: no `adb`/`emulator`/`sdkmanager`/`avdmanager`
anywhere under `$HOME`, no `cmdline-tools`, no Android Studio, no SDK in any standard
location, `~/.android` holding only `analytics.settings` and `cache` (no `avd/`),
`apps/mobile/android/local.properties` carrying only `flutter.sdk=` with **no `sdk.dir`**,
and **no Android job, script or documented emulator workflow anywhere in the repository or
its CI**. There was nothing to reuse, so the toolchain had to be built.

### 19.2 Toolchain installed from nothing — this part succeeded

| Component | Version | Result |
|---|---|---|
| cmdline-tools | 12.0 | installed (Google official zip; the Homebrew cask fails on this machine with `Failed to quarantine … xattr: No such file: …kotlin-compiler-mvn.jar`, and `--no-quarantine` was removed in Homebrew 7) |
| platform-tools | 37.0.1 | installed — `adb` 1.0.41 working |
| platforms;android-35 | 2 | installed |
| emulator | 37.1.11 | installed |
| system-images;android-35;google_apis;arm64-v8a | rev 9 | installed (1.78 GB, direct from `dl.google.com` after `sdkmanager` failed twice with a bare `Warning: Failed to download package!`) |
| SDK licences | — | 14 accepted |
| AVD `qa35` | Pixel 6, API 35, arm64-v8a | **created**, and `flutter emulators` lists it: `qa35 • qa35 • Google • android` |

### 19.3 Boot blocked — disk, with exact numbers

```
FATAL | Not enough space to create userdata partition.
        Available: 2201.36 MB at ~/.android/avd/qa35.avd, need 7372.80 MB.
```

The 7,372.80 MB figure is a fixed emulator pre-flight requirement, **not** the configured
partition size: it was reproduced after setting `disk.dataPartition.size = 1600M`, removing
the 512 MB SD card and passing `-partition-size 2048`. Two boot attempts, same FATAL.

Disk was also reclaimed along the way — Homebrew caches pruned twice, the failed cask
download removed, the QA web build deleted, temp logs cleared — which is why free space
*rose* from 942 MiB to ~2.2 GiB mid-run. It is still **≈5.1 GB short**.

**ANDROID: ENVIRONMENT_BLOCKED — insufficient disk, ~5.1 GB short of the emulator's
7.2 GB pre-flight requirement.** This is not a tooling gap any more: the SDK, system image
and AVD are all installed and staged, and the gate should clear on the next attempt once
~5–6 GB is free. Freeing that means deleting data this QA pass does not own.

Not attempted, deliberately: installing Xcode (explicitly excluded by the owner), and
deleting user data to make room.

---

## 20. Design handoff intake — complete, and implementation is BLOCKED by the package itself

### 20.1 Where the design lives

`/Users/dmac/Documents/projects/helix-design-references/12circle fitness/fitness-app-board/` —
a 468 KB `12Circle Fitness - Complete Board.dc.html`, seven governance docs, and five
images. Read-only; nothing there was modified. It is **outside** the app repo, which the
in-repo audit itself notes (§17.5: *"`docs/design/` does not exist in the repo and no design
board artifact exists"*). `docs/design/` in this repo holds only the 2026-09-09 UI audit.

### 20.2 The package forbids its own application

- `12CIRCLE-FITNESS-DESIGN-CLOSURE.md:3-4` — *"Status: design package closed for review.
  No Dart, Flutter, provider, route, Supabase or backend code has been modified.
  **Nothing has been implemented.**"*
- `12CIRCLE-FITNESS-PHASE-2-DESIGN-SYSTEM.md:11` — *"**⚠ SPECIFICATION ONLY — DO NOT APPLY
  FROM THIS DOCUMENT**"*

**Implementation cannot begin on this package's own terms.** That is the single decisive
finding of this intake.

### 20.3 Correction: Home and Active Workout are not recorded as "rebuilt"

The brief describes Home and Active Workout as newly rebuilt. The design documents do not
support that. Both are **locked anchors** present since the first pass (Wave 3 crosswalk
classes them `A — designed and locked`). The only structural change recorded is
DESIGN-CLOSURE §5: *"the five core screens originally sat in fixed 844px frames with
`overflow: hidden`, which clipped content. They now flow intrinsically"* — a layout-flow
fix, not a redesign. **Home does not appear in the Locked-Screen Change Register at all**;
Active Workout appears once, for an exercise reference thumbnail, marked **NEEDS OWNER
REVIEW**. The register carries 7 element-level alterations total — 2 approved, 5 awaiting
review — and opens by correcting its own prior report (*"The list was wrong in both
directions"*).

What *is* new: Waves 1–4 (77 frames) plus 4 promoted auth screens, and five genuinely new
products with no Flutter counterpart — Post detail + comments, Create post, Pod detail,
Challenge leaderboard, Cancellation sheet — plus a route for the built-but-unreachable
`EventTicketScreen`.

### 20.4 The spec conflicts with the shipped theme on nearly every token

| Token | Spec | Repo `twelve_circle_theme.dart` |
|---|---|---|
| accent | `#7C3AED` | `#7C5CFF` — **the spec explicitly rejects this value** |
| radiusCard | 16 | **28** |
| radiusButton | 12, flat | **999 (pill)** |
| fonts | Schibsted Grotesk ×3 | Outfit / Inter / Rajdhani |
| motion | `emphasized`, 200 ms | `spring`, 300 ms |
| textTertiary | `#8B8595` (4.81:1 floor) | `#5B646F` — **fails AA** |
| heading weights | "Nothing above 500" | w700/w800 in `helix_theme_builder.dart` |
| displayWeight / displayTracking | required | **fields do not exist** in `HelixSemantics` |

`HelixTypeScale` has no `w300`; `helixNumeric` has no `FontFeature.tabularFigures`, so the
spec's tabular rule is currently unimplementable. Spacing is the one dimension that already
agrees (`x5=20, x8=32, x12=48`).

Applying this spec means changing every colour, radius, font and motion token in the app —
a wholesale visual redesign. That is a product decision, explicitly outside QA's mutation
authority, and it is also what the spec's own banner forbids doing from the document.

### 20.5 Handoff gaps — 32 recorded

Counts disagree across the package itself (README 110 frames / board header 88 / closure 64),
and the coverage matrix marks screens "Designed" that the Wave 3 crosswalk marks
`Design? no`. Materially: no white/mono brand mark (supplied artwork is black-on-white,
rendered in the board with `filter: invert(1)` and *"Approved for the design artifact
only"*); no avatar, class-category, event or progress photography; only 5 of a claimed 22
images ship. Undrawn: role-unauthorized state, email verification, offline as a real frame,
10 of 27 intake pages, and every money-path surface (`/subscription`, `/payment-success`,
`/payment-cancel`). Unresolved interactions include the AI Coach dashboard-vs-chat switch
(*"Not decidable from source"*), and the nav contract conflicts between two design documents
(slot 3 `/nutrition` vs `/meals-dashboard`; whether `coachingModeProvider` changes the
Workouts destination).

### 20.6 Status

**DESIGN HANDOFF INTAKE: COMPLETE.**
**NEW SCREEN INTEGRATION: BLOCKED — OWNER DECISION REQUIRED**, on three independent
grounds: the package forbids application, 32 handoff gaps remain open (including 4+
decisions the closure doc itself lists), and applying it constitutes a product-wide visual
redesign QA may not decide.

Consequently **functional QA of new screens, Android QA of integrated screens, and the
final premium visual QA cannot begin** — there are no integrated new screens to test. The
brief's own sequencing (intake → integration → functional QA → Android QA → visual QA)
stops at the first gate.

---

## 21. CORRECTION OF RECORD — §20 audited an INCOMPLETE copy of the package

§20 stands as written history, and its central ruling is now **withdrawn**. The cause is
not new reasoning; it is a second, complete copy of the same package.

### 21.1 What was actually audited in §20

`~/Downloads/12circle-fitness-new-screens.zip` (1,826,216 bytes, sha256
`d4438803deee0984…`, dated 2026-09-22 19:53) unpacks to `fitness-handoff/` — **21 files**.
The directory §20 audited holds **8 entries**. Comparing them file by file, through a pipe,
with nothing extracted:

| File | zip | `fitness-app-board/` |
|---|---|---|
| `12Circle Fitness - Complete Board.dc.html` | `edcce7a51d6a0a87…` | `edcce7a51d6a0a87…` — **identical** |
| `manifest.json` (340 KB) | present | **absent** |
| `DESIGN_HANDOFF.md` | present | **absent** |
| `IMPLEMENT-THIS.md` | present | **absent** |
| `capture-references.mjs` | present | **absent** |

Same design — the board is byte-identical. The on-disk copy was missing precisely the
files that carry the package's authority and its machine-readable contract. §20 was a
sound reading of an unsound input.

### 21.2 The decisive blocking finding falls

§20.2 held that "the package forbids its own application," resting on
`PHASE-2-DESIGN-SYSTEM.md:11` — *"SPECIFICATION ONLY — DO NOT APPLY FROM THIS DOCUMENT."*

`IMPLEMENT-THIS.md`, absent from the audited copy, is titled *"IMPLEMENT: 12Circle Fitness
— rebuilt screens"* and opens: *"You are implementing the redesigned 12Circle Fitness
screens in the existing Flutter app. The design is the source of truth."* Its step 4 then
points **at** the banner-bearing document: *"Read
`docs/12CIRCLE-FITNESS-PHASE-2-DESIGN-SYSTEM.md`. Tokens go into Helix Tier 1–3 as written
there. No parallel theme."*

The banner scopes to that one document — do not implement *from the spec sheet alone* —
not to the package. Authority sits in `IMPLEMENT-THIS.md` + `manifest.json`.
`DESIGN_HANDOFF.md:4` states the status outright: **"READY FOR CLAUDE CODE."**

### 21.3 The gap count falls: 32 → 9

§20.5's 32 gaps were largely reconstructed by hand because the register was missing.
`manifest.json → implementationGaps` carries **9**, `GAP-01…GAP-09`, of which
`IMPLEMENT-THIS.md` marks exactly three as owner decisions: **GAP-07** (intended states the
backend cannot reach), **GAP-08** (Score frame semantic mismatch), **GAP-09** (event ticket
unrouted). Measured manifest totals: 110 screens · 50 routes · 28 components · 19 tokens ·
108 icons · 600 interactions.

### 21.4 What SURVIVES the correction

- **The 88-vs-110 frame-count inconsistency is real.** The board HTML — the byte-identical
  file, the declared source of truth — still says `88 screens` in three places, while
  `README.txt` and `manifest.json` say 110. Unchanged internal contradiction.
- **§20.4's token conflict table stands unaltered.** Every measured divergence (accent
  `#7C3AED` vs `#7C5CFF`, radiusCard 16 vs 28, radiusButton 12 vs 999, three font families,
  motion, heading weights) is still true of the shipped theme.

What changes is who decides them. The package *rules* on these conflicts rather than
raising them: accent `#7C3AED`, accent text `#A78BFA`, `--dim` `#8b8595` (*"Not `#6a6572`
— that was a regression"*), *"Schibsted Grotesk, nothing above weight 500,"* tokens into
Helix Tier 1–3, *"No parallel theme."* That is a direct answer to the open **D-2**
design-system contract decision.

It also answers **D-3**, which this sweep deliberately left open. `IMPLEMENT-THIS.md`:
*"Every interactive target ≥ 44×44. Several current source controls are 18–40px; the design
floor wins."* That names the 40×40 `_IconBtn` hit box (§4) and the 20×20/22×22 password
toggle this sweep declined to alter without an owner ruling.

### 21.5 Revised status

**NEW SCREEN INTEGRATION: STILL OWNER-GATED — but on one ground, not three.**

Two of the three grounds in §20.6 are withdrawn. The surviving one is unchanged in
substance and is the only real question: implementing this package changes every colour,
radius, font and motion token in the app. That is a product-wide visual redesign, and QA
does not hold the authority to start one on its own initiative.

One procedural matter attaches to it. The owner's standing instruction for this workstream
is *"Do NOT trust any existing design package found on the machine."* This package was
found on the machine, in `~/Downloads`. It is complete, internally consistent on its own
IDs, and self-identifying — but its provenance is a download, not an owner handoff. **QA
records it as verified-complete and refers the adoption decision upward rather than
inferring authorization from the package's own say-so.** Under this workstream's own rule:
an authorization problem is not solved by making the change anyway.

Nothing in the package was extracted, applied, or copied into the repository. The zip and
the reference directory were read only.

---

## 22. Android runtime gate — toolchain provisioning

§19 closed with the Android gate staged but unopened. The emulator now boots and Flutter
sees it; this section records what stood between those two facts, because every obstacle
was an environment defect rather than a product defect, and the distinction is the whole
point of the gate.

### 22.1 Emulator — open

```
emulator-5554   device   product:sdk_gphone64_arm64   model:sdk_gphone64_arm64   device:emu64a
sys.boot_completed = 1 · Android 15 (API 35) · arm64-v8a · 1080x2400 @ 420dpi
```

Flutter enumerates it as `sdk gphone64 arm64 (mobile) • emulator-5554 • android-arm64`.
The QA backend is reachable from the host (`/auth/v1/health` → **200**) and the emulator
has working egress (0% packet loss). The nonsensical RTT the emulator reports
(`739477957506295 ms`) is a known emulator clock artifact, not a network fault.

Launch target: `com.twelvecircle.circle_fitness/.MainActivity`. Dart defines resolve to
Supabase ref `eyqtldjqpgpljlqvpowh` — the **QA** project declared in
`supabase/expected_applied.json`, so runtime exercises QA and not production.

### 22.2 Why an NDK is required at all

`android/app/build.gradle.kts:10` sets `ndkVersion = flutter.ndkVersion`, but the binding
requirement comes from a plugin that actually compiles C++:

```
jni-1.0.0/android/build.gradle:55-58
    externalNativeBuild { cmake { path "../src/CMakeLists.txt" } }
```

`jni` is **transitive**. The only direct dependency is `speech_to_text: ^7.4.0`
(`pubspec.yaml:45`), which reaches `jni`/`jni_flutter` (`pubspec.lock:818` —
`dependency: transitive`). One voice-input package therefore imposes a 2.8 GB NDK and a
CMake toolchain on every Android build. Recorded as a build-cost observation; changing a
dependency is not QA's call.

### 22.3 `sdkmanager` cannot install packages on this machine

The documented route produces **stub directories containing only `.installer`** and no
payload — 4.0 KB where an NDK should be. AGP then fails:

```
[CXX1101] NDK at .../ndk/28.2.13676358 did not have a source.properties file
```

This is the identical failure mode that defeated the system-image install in §19, so it is
a property of this machine's `sdkmanager`, not of any one package. Both the NDK and CMake
were therefore fetched directly from `dl.google.com`, the workaround already proven.

### 22.4 A streaming extraction silently corrupted the toolchain

To avoid holding a 688 MB archive and its 2.8 GB expansion simultaneously on a volume with
4.8 GB free, the first NDK install was streamed — `curl … | tar -xf -`. It reported
success and produced a correct-looking tree with a valid `source.properties`. It was
nonetheless **structurally corrupt in two ways**:

- **Mode bits lost.** 179 binaries in a single `bin/` were non-executable; a magic-number
  scan found 394 files across the NDK and CMake needing `+x`.
- **Symlinks materialized as text.** `toolchains/llvm/prebuilt/darwin-x86_64/bin/clang` was
  an 8-byte regular file containing its target's name rather than a link to `clang-20`.

libarchive's streaming zip reader does not carry zip symlink and permission attributes.
The mode bits were repairable; the symlinks were not repairable by inspection without
guessing, so both packages were deleted and re-fetched with `unzip`, which restores link
and permission attributes correctly.

**This is worth recording as method, not just incident.** A stream-extracted toolchain
reports success, passes a file-existence check, and produces a valid version string — and
would have failed later inside a native compile, where the symptom would have looked like a
product or plugin defect. Verifying a provisioned toolchain means executing its binaries,
not listing its files.

### 22.5 Disk was the real constraint, and no user data was deleted

The volume (APFS, 89% full) offered 4,856 MB. A single `assembleDebug` consumed ~2.67 GB
before producing any `build/` directory, of which ~1.9 GB was transient daemon scratch
returned on exit and ~730 MB was persistent cache growth. Two runs were aborted by a disk
watchdog at 192 MB and 321 MB free — **the watchdog killed the build; the build did not
fail.** Recording that distinction matters: neither abort is evidence about the product.

Reclaimed, in order, and only regenerable machine-level caches:

| Reclaimed | Size | Why it was safe |
|---|---|---|
| `~/.gradle/caches/{9.2.0,9.3.1,9.4.1}` | 1.76 GB | Other Gradle versions; this project pins `gradle-9.1.0-all` |
| `~/.gradle/daemon` | 95 MB | Daemon logs |
| `~/Library/Caches/com.microsoft.VSCode.ShipIt/update.*` | 1.4 GB | A staged, undelivered app update |
| `~/.npm/{_cacache,_npx}` | 2.4 GB | Package caches; re-fetched on demand |
| `~/.gradle/caches/8.7` | 164 MB | Unused Gradle version |

Kept deliberately: `~/.gradle/caches/modules-2` (this build's dependency cache),
`system-images/android-35` (mounted by the running emulator), and the 46 GB Docker
container directory — **images and volumes are user data and were not touched**. Nothing
in any repository, and no document, was deleted.

Not attempted, deliberately: installing Xcode (excluded by the owner), and deleting user
data to make room.

### 22.6 P1 — the Android app could not be built, and no gate would ever have said so

With the toolchain finally sound, the build failed again — and this failure is **not an
environment defect**:

```
Execution failed for task ':app:checkDebugAarMetadata'.
> An issue was found when checking AAR metadata:
    1. Dependency ':flutter_local_notifications' requires core library desugaring
       to be enabled for :app.
```

`flutter_local_notifications: ^18.0.1` is `dependency: "direct main"`. Version 18.x
declares in its AAR metadata that the consuming app must enable core library desugaring.
`apps/mobile/android/app/build.gradle.kts` did not, and
`git log -S'coreLibraryDesugaring' -- apps/mobile/android/` returns **nothing** — it has
never been configured in this repository's history. The file is still the stock Flutter
template, TODOs for `applicationId` and the release signing config intact.

The check runs before any code is compiled, so this is not a marginal or
configuration-dependent failure: **`flutter build apk` could not succeed on this branch at
any point.**

#### Why CI is green anyway

CI's `flutter` job (`.github/workflows/ci.yml:188-220`) runs exactly four things:

```
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build web --dart-define-from-file=dart_defines/qa.json
```

`flutter build web` is the **only** build. Across both workflows, no job runs
`flutter build apk`, `assembleDebug`, or `appbundle`, and there is no iOS build either.

That is the finding, and it is larger than the missing flag. **The five consecutive green
pipelines recorded in §18 never once compiled the shipped product for the platform it
ships on.** CI proves the web target compiles; the Android target was broken the whole
time, and green CI was never capable of noticing. A unit and analyzer suite cannot detect
an AAR metadata contract — only a build can.

#### Repair applied

Minimal and prescribed by the error and by the plugin's own requirement — no product
behaviour, no design, no gate weakened:

```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true      // + explanatory comment
    …
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

The build then advanced past `checkDebugAarMetadata` into native compilation.

**Recommended and NOT done unilaterally:** adding an Android build job to CI. That changes
the pipeline's contract and its cost, and belongs to the owner. Recorded here as the
remedy that would convert this from a defect that recurs into one that cannot.

### 22.7 Forward-looking build-health warning (recorded, not acted on)

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
mobile_scanner, sign_in_with_apple, speech_to_text
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

Three direct dependencies will break the Android build on a future Flutter release.
Upgrading or replacing a dependency is a product decision, so this is logged, not
actioned. It compounds §22.6: without an Android build in CI, the day this stops being a
warning and becomes an error will be discovered by a person, not by a gate.

---

## 23. ANDROID RUNTIME QA — the gate is open, and it immediately earned its keep

Everything below was observed on a running Android app. Device: `emulator-5554`,
`sdk_gphone64_arm64`, Android 15 (API 35), arm64-v8a, 1080×2400 @ 420 dpi (2.625 px/dp).
Build: `app-debug.apk`, 126 MB, `--dart-define-from-file=dart_defines/qa.json` → QA
Supabase `eyqtldjqpgpljlqvpowh`. Evidence (screenshots + `uiautomator` XML dumps) in the
session scratchpad.

```
Performing Streamed Install → Success
am start -W -n com.twelvecircle.circle_fitness/.MainActivity
  Status: ok · LaunchState: COLD · TotalTime: 5009 ms
```

No `FATAL`, no crash-buffer entries, no `E/flutter` at any point in this pass. The only
log noise is `ChimeraSrvcProxy` from Play Services (pid 2125), not the app.

### 23.1 P1 — a raw Dart exception is shown to the user *(found at runtime, repaired)*

Signing in with a wrong password displayed this, in a SnackBar, to the user:

```
AuthApiException(message: Invalid login credentials, statusCode: 400,
code: invalid_credentials)
```

That is `AuthException.toString()` verbatim (`gotrue-2.21.0`,
`lib/src/types/auth_exception.dart`). A mistyped password shows a consumer a Dart object
dump carrying a class name, an HTTP status code and a backend error code.

**It was not one screen. It was all four** — the entire unauthenticated surface, the first
thing every new user touches:

| Site | Was |
|---|---|
| `login_screen.dart:101` | `_showError(authState.error.toString())` |
| `signup_screen.dart:61` | `error: (e, _) => _showError(e.toString())` |
| `reset_password_screen.dart:49` | `_snack(e.toString())` |
| `forgot_password_screen.dart:43` | `SnackBar(content: Text(e.toString()))` |

`login_screen.dart` convicts itself: its Google (`:79`), Apple (`:86`) and empty-field
(`:92`) paths all use written copy — *"Could not start Google sign-in. Please try again."*
Only the primary email/password path dumps the object. The intent was never in doubt; the
main path was simply missed.

**Repair — and it invents no product copy.** `AuthException` already carries a `message`
field that gotrue documents as *"Human readable error message associated with the error."*
The defect was stringifying the **wrapper** instead of reading that field. New seam
`lib/core/errors/auth_error_text.dart` returns `error.message`, so the wording of every
auth error remains exactly what the auth provider chose. The raw object now goes to
`reportError` (`lib/core/observability/app_failure.dart`) — the status code and error code
belong in an operator's console, not a SnackBar. The sink already existed and these
screens simply were not using it.

The one string this repository adds is the fallback for errors that are **not**
`AuthException` and therefore carry no human-readable message: *"Something went wrong.
Please try again."* Flagged as the only copy decision in the change.

Guarded by **A-G2** in `test/unit/presentation_drift_guard_test.dart`, mutation-tested:
reintroducing `authState.error.toString()` at `login_screen.dart:108` fails the guard, and
restoring returns it to green. The guard strips `//` comments first, so the explanatory
comment that quotes the old expression does not self-trigger. Scoped deliberately to
`features/auth/presentation` — the same shape exists elsewhere in the tree and is recorded
below rather than pinned by a guard that would need weakening to pass.

### 23.2 P1 — the app's user-facing name is `circle_fitness` *(owner decision)*

The first thing the OS showed the user was *"Allow **circle_fitness** to send you
notifications?"* — the Flutter project directory name, in a system dialog.
`AndroidManifest.xml:11` sets `android:label="circle_fitness"`. On Android that string is
the home-screen name, the app-drawer name, the Settings entry and every permission dialog.

The platforms also disagree: iOS `Info.plist` declares `CFBundleDisplayName` =
**"Circle Fitness"**, while `CFBundleName` is `circle_fitness`. Neither is the product's
name.

**Referred, then repaired.** That `circle_fitness` was wrong was never in question; *which*
string replaced it was branding — three candidates, no authority to pick. Referred to the
owner, who ruled on 2026-09-22: **"12Circle Fitness"**, and both platforms aligned to it.

```
AndroidManifest.xml:11   android:label="12Circle Fitness"
ios/Runner/Info.plist    <key>CFBundleDisplayName</key><string>12Circle Fitness</string>
```

Guarded by **A-G3**, mutation-tested: restoring `android:label="circle_fitness"` fails the
guard. The guard asserts both platforms against the same constant, so Android and iOS
cannot drift apart again — which is how they came to declare two different names in the
first place.

### 23.3 Notification permission is requested on cold start, before any UI

`POST_NOTIFICATIONS` is requested during launch: the first frame the user sees is a system
dialog over an empty grey screen, with the app's value proposition not yet shown. The
top-resumed activity at +5 s was `GrantPermissionsActivity`, not `MainActivity`. No priming
screen precedes it. Recorded as a product/UX decision, not repaired.

### 23.4 Accessibility — measured on-device, not inferred

From `uiautomator` dumps, converted at 2.625 px/dp. The 44 dp floor is WCAG 2.5.5 / the
design package's *"Every interactive target ≥ 44×44."*

| Control | Size (dp) | Accessible name | Verdict |
|---|---|---|---|
| Password visibility toggle | **19.8 × 20.2** | **none** | fails size **and** name |
| "Forgot password?" | 122.3 × **20.2** | present | fails size |
| "Don't have an account? Sign Up" | 219.4 × **19.8** | present | fails size |
| Email / password inputs | 324.6 × 23.2 | **none** | see note |
| Sign In | 363.4 × 58.3 | present | passes |
| Google / Apple | 175.6 × 56.0 | present | passes |

**The password toggle is the worst case and confirms a static prediction.** §4 flagged a
20×20/22×22 toggle from source and declined to change it pending **D-3**. Runtime now
measures it at **19.8 × 20.2 dp — under half the 44 dp floor — and carries no accessible
name at all**, so a screen-reader user cannot find it or know what it does. Static analysis
predicted it; runtime proves it.

**Note on the inputs.** Their 23.2 dp height is *not* a target defect: each sits inside a
clickable wrapper measuring 363.4 × 57.9 dp, so the tappable area is compliant. Their real
defect is the missing accessible name — the visible "Email address" / "Password" strings
are placeholder hints and are not exposed. The email node reports
`text='qa.tester@example.com'`, which is its *value*, not a label; it appeared only because
this pass typed into it.

Also observed: interactive controls surface as `android.view.View` with `clickable=true`
rather than as buttons, so assistive technology announces the label without the role.
Lower confidence — Flutter's semantics bridge commonly reports `View` — recorded for
follow-up rather than asserted as a defect.

### 23.5 What passed, and is worth stating plainly

- **Keyboard insets are correct.** Focusing email raises the IME
  (`mInputShown=true`), content resizes, the footer relocates above the keyboard, and
  nothing is clipped or obscured. The large gap visible on the idle login screen is a
  deliberate spacer that absorbs the keyboard, not dead space.
- **Password masking is handled correctly and securely.** Masked, the field reports
  `password=true` and **withholds its value from the accessibility tree** (`text=''`).
  Revealed, it reports `password=false` with the value present. The toggle works; only its
  size and label are wrong.
- **Focus affordance** is clear — a purple focus ring on the active field.
- **Navigation** welcome → sign-in works; no crash, no jank, no error output.

### 23.6 A correction of my own reading

While viewing the sign-in screenshot I suspected text was painted under the status bar. It
was not. The `uiautomator` dump places the only candidate node, *"Don't have an account?
Sign Up"*, at `[252,2248][828,2300]` — the bottom of the screen. The apparent artifact was
my misreading of the image. Recorded because a QA document that only keeps its confirmed
suspicions is not an honest instrument.

### 23.7 Authenticated runtime reached — and the intake flow has a semantics defect

Signed in on-device with the committed QA fixture identity `p1-victim@qa.12circle.test`
(`supabase/tests/security/setup-identities.mjs`, the same identity `uix1_booking_e2e_test`
uses). Authentication succeeded against QA, proven by the persisted session key:

```
shared_prefs/FlutterSharedPreferences.xml
  <string name="flutter.sb-eyqtldjqpgpljlqvpowh-auth-token"
```

The ref matches the QA project declared in `expected_applied.json`. No `E/flutter`, no
`AppFailure`, no crash across the whole authenticated pass. The router sent this user to
`intake_flow_screen.dart`, which is correct: the fixture has no completed intake.

**The intake welcome page is a single accessibility node.**

```
[0,0][1080,2400]  411.4 x 914.3 dp  clickable=true
  'MOVE\nBETTER\nFEEL\nSTRONGER\nLIVE\nHEALTHIER\nGet Started'
```

The entire screen — headline and button alike — collapses into one merged, clickable node.
"Get Started" is therefore not separately focusable, and a screen reader announces the
whole page as one run-on string.

**This was checked against two false explanations before being recorded.** A single dump
proves nothing here, because Flutter builds its semantics tree lazily and the preceding
`am force-stop` reset the process. (a) A second dump after settling returned the identical
single node, so it is not a warm-up artifact. (b) Advancing one page returned **11 discrete
nodes**, so semantics is live and working on this screen — the merge is specific to the
page, not to the session.

**A whole-screen clickable node is present on intake pages generally**, absorbing static
text. On page 2 it appears as:

```
[0,0][1080,2400]  411.4 x 914.3 dp  clickable=true  'Your Profile\nTell us a little about yourself.'
```

Page 1 has no other interactive child carrying its own semantics, which is why everything
collapses into it there. The login screen shows no such node, so this is specific to
`intake_flow_screen.dart`. `_WelcomePage` itself is a plain `Stack` and "Get Started" is a
bare `GestureDetector` (`:928`) with no `Semantics(button: true)`; the `PageView` uses
`NeverScrollableScrollPhysics`. **The precise origin of the full-screen clickable node is
not yet isolated, and is recorded as unresolved rather than guessed at.**

Ruled out by inspection: there is no global gesture or `unfocus` wrapper in `main.dart` or
`app_router.dart`, `_Glow` (`:493`) is a non-interactive `Container`, and the `Scaffold`
itself carries no `onTap`. The one correlation the evidence supports — stated as a
correlation, not a cause — is that both screens exhibiting the node host the `PageView`,
while the login screen, which has none, shows no such node. Worth starting there.

The `onboarding_screen.dart` route does **not** merge: back-navigating to it exposed four
discrete nodes (`WELCOME TO YOUR JOURNEY`, the headline, `Get Started`, `Already a member?
Sign In`). The defect is specific to the intake flow, not to pre-auth screens generally.

### 23.8 P2 — the first screen of the app overflows in landscape, clipping its own CTA

**No orientation lock exists anywhere.** There is no `SystemChrome.setPreferredOrientations`
in Dart and no `android:screenOrientation` in the manifest, so the app fully supports
landscape and Android will rotate it. `AndroidManifest.xml:20` declares
`configChanges="orientation|screenSize|…"`, so the Activity handles rotation itself.

Rotated to landscape (`mRotation=ROTATION_90`, `w914dp h411dp`, bounds 2400×1080), the
first screen a new user sees renders Flutter's own overflow diagnostic across its primary
call to action:

```
BOTTOM OVERFLOWED BY 39 PIXELS
```

The yellow-and-black stripe is painted over the "Get Started" button and its label is
clipped to illegibility. Reproduced deterministically on a fresh cold start in landscape,
not only on rotation.

**Correct attribution matters here and nearly went wrong.** The rendered screen is
`lib/features/home/presentation/splash_screen.dart`, **not**
`features/onboarding/presentation/onboarding_screen.dart`. The two are easily confused:
both open "WELCOME TO YOUR JOURNEY" with the same subtitle and the same "Already a member?
Sign In" footer. They are distinguished by the headline — `splash_screen.dart:26` cycles
`_phrases` (*"Train like\nyou mean it" → "Push past\nyour limits" → "Stronger\nevery rep"*),
which is why the headline differed between launches, while `onboarding_screen.dart` has the
fixed "TRAIN LIKE\nYOU MEAN IT" and a slide-to-confirm CTA rather than a tap button.

**Cause**, `splash_screen.dart:109` — a `Column` under `SafeArea > Padding` whose
fixed-height children cannot fit 411 dp:

| Child | Height |
|---|---|
| brand rings + logo (`:111`) | 70 |
| `Spacer()` (`:119`) | ≥ 0 — can shrink to nothing, not below |
| eyebrow + `SizedBox` (`:122-124`) | ~15 + 12 |
| cycling headline (`:127`) | **fixed `SizedBox(height: 96)`** |
| `SizedBox` + subtext + `SizedBox` (`:132-138`) | 16 + ~22 + 26 |
| CTA + `SizedBox` + Sign In (`:140-142`) | ~60 + 18 + ~20 |

The `Spacer` absorbs surplus in portrait and reaches zero in landscape, leaving the fixed
remainder 39 px over budget.

**Not repaired, and the reason is not timidity.** The obvious one-line fix does not exist:
a `Spacer` cannot live inside a `SingleChildScrollView` (it requires bounded height), so
making this scroll means restructuring the hero screen's layout. The alternative — locking
the app to portrait — is a product posture, and every comparator this product is measured
against (Apple Fitness+, WHOOP, Nike Run Club, Strava) locks phone UI to portrait. Both
routes are product decisions:

1. **Lock phone orientation to portrait** — one line, matches the category, and makes the
   landscape layout question moot across all 91 routes rather than only this screen.
2. **Support landscape properly** — restructure this `Column` and audit the other routes,
   none of which have been checked in landscape.

Recorded for decision. Note that option 2 is a larger commitment than this one screen: no
landscape design exists in the design package either, whose frames are all 390×844.

Intake page 2 (`Your Profile`) measured clean otherwise — every interactive target
≥ 44 dp (inputs 363.4 × 51.0 dp, Male/Female 175.6 × 51.0 dp, date 363.4 × 54.9 dp).

Two observations held back deliberately:

- **"Continue" reports `clickable=false`** (`[53,2159][1028,2295]`). Gender and Date of
  Birth were unset at the time, so a disabled Continue is very likely *correct* behaviour.
  Not recorded as a defect without testing the enabled state.
- **Text inputs again expose their value as their name** — the nodes read `'P1'` and
  `'victim'`, while `'First Name'` and `'Last Name'` are separate non-clickable labels.
  Same pattern as §23.4; consistent, and consistent with the inputs having no accessible
  name of their own.
