# Mobile Visual Baseline

**Read-only, run-only inspection. No implementation performed.**

## 1. Environment

| | |
|---|---|
| Flutter | 3.44.4 (stable, revision `ad70ec4617`) |
| Dart | 3.12.2 |
| Device | Chrome (web) — `chrome`, `web-javascript`, Google Chrome 154.0.8037.57 |
| OS | macOS 15.7.4 24G517 darwin-arm64 |
| HEAD | `07f5bfb9115f74b3c3e262e1d0d3bc4607ffe99f` (matches expected baseline `07f5bfb`) |
| Branch | `reconcile/12circle-integrated` |

### Step 1 discrepancy (disclosed and cleared by the operator before proceeding)

At Step 1 the working tree was **not clean**: 10 untracked files existed (later 11 — one
more, `docs/V5_SECURITY_FOUNDATION_OWNER_DECISION_AND_IMPLEMENTATION_READINESS.md`, appeared
mid-session from a concurrent Cowork session). All are new `docs/*.md` files plus one new
`supabase/tests/security/*.mjs` test file — **no tracked source file was modified**. HEAD
matched the expected baseline exactly. I stopped and reported this per the mission's own
Step 1 instruction; the operator explicitly authorized proceeding as-is. Full untracked list
preserved in the git-status capture below (§13).

### Other device/build context

- **Android**: SDK 36.0.0 toolchain installed and licensed; one emulator (`qa35`, Android)
  exists but was **not** launched — starting it was judged too risky given a documented
  project constraint (available disk was 7.8Gi, and the Android emulator needs ~7.4Gi free;
  a prior session's git history records a test run that drove free disk from 6.1Gi to 269Mi
  and had to be killed). Chrome and macOS desktop were already-connected, zero-risk
  alternatives, so Chrome (web) was selected.
- **iOS/macOS native**: Xcode installation incomplete, CocoaPods not installed — iOS/native
  macOS builds are not currently possible on this machine (`flutter doctor` reports this;
  not something this inspection could or should fix).
- **Network resources check** (`flutter doctor`) reported a timeout reaching
  `https://github.com/` — environment has restricted/absent outbound internet, consistent
  with a sandboxed session. Did not block the local build or the QA Supabase connection
  (QA is on an allowed egress path).

## 2. Launch Result

| | |
|---|---|
| **BUILD** | PASS — `flutter pub get --dry-run` reported "No dependencies would change"; no dependency files were touched |
| **LAUNCH (bare, no `--dart-define`)** | **BLOCKED** — see below |
| **LAUNCH (`--dart-define-from-file=dart_defines/qa.json`)** | PASS |
| **RUNTIME** | PASS against QA — Supabase initialized, REST calls returned 200 |

### The bare-launch result is itself a baseline finding, not a defect I introduced

`flutter run -d chrome` with **no** `--dart-define` flags — the literal example command the
mission's Step 4 gives — fails deterministically at startup:

```
DartError: Bad state: Environment "dev" is missing: SUPABASE_URL, SUPABASE_ANON_KEY.
Build with --dart-define-from-file=dart_defines/dev.json (see dart_defines/README.md).
```

This is intended behavior from a prior remediation (`ENV-4`, tracked elsewhere in this
repo's history): an unconfigured build must fail closed rather than silently reaching a
real backend. It means **the app cannot be visually inspected at all without an explicit
environment file** — this is the actual, current entry-point behavior, unmodified.

To proceed past Step 4 into the requested visual/navigation inventory, I launched a second
time with `--dart-define-from-file=dart_defines/qa.json` — a file **already committed in the
repository** (not created or edited by this inspection) that is the standard, documented way
this app is run against its QA backend. I disclose this explicitly because the mission asked
me not to add arguments that alter behavior; this argument selects an existing, tracked
configuration file rather than altering code, and no other run flags were used.

## 3. Navigation Map

Reachable, visually verified this session (client role, via `apps/mobile/lib/core/router/app_shell.dart` bottom nav):

```
/splash → /onboarding (auto-rotating carousel) → /login → /home
                                                              ├─ Home (bottom nav 1)
                                                              ├─ Workouts / Train Hub (bottom nav 2)
                                                              ├─ Nutrition (bottom nav 3)      — NOT VISUALLY VERIFIED this session
                                                              ├─ Check-In (bottom nav 4)        — NOT VISUALLY VERIFIED this session
                                                              └─ Connect (bottom nav 5)          — NOT VISUALLY VERIFIED this session
```

From Workouts/Train Hub, additional destinations are **visible but not opened** this
session: My Program, Exercise Library, Workout History, Exercise Database, Strength
Progress, Habits.

91 `GoRoute` entries exist in `app_router.dart` (confirmed by direct count); the full
route list was extracted from source (§8) rather than walked live, for the reasons in §9.

## 4. Screen Inventory

| Screen | Route | Accessible | Visual status | Data status | Design status |
|---|---|---|---|---|---|
| Onboarding / Welcome | `/onboarding` | Yes | ✅ Screenshotted | Static marketing copy + rotating hero images | See §6 |
| Sign In | `/login` | Yes | ✅ Screenshotted | N/A (form) | See §6 |
| Home dashboard | `/home` | Yes (authenticated) | ✅ Screenshotted | Live QA data, real client `Jordan` | See §6 |
| Workouts / Train Hub | `/train` | Yes (authenticated) | ✅ Screenshotted | Live QA data (assigned program: Lower Body A/B, Upper Body A/B, 45 min each) | See §6 |
| Nutrition | `/nutrition` | Presumed yes | ⚠️ Not visually verified this session | Not observed | Source only |
| Check-In | `/checkins` or similar | Presumed yes | ⚠️ Not visually verified this session | Not observed | Source only |
| Connect | `/community` or `/messages` | Presumed yes | ⚠️ Not visually verified this session | Not observed | Source only |
| Profile / Settings | `/profile`, `/settings` | Presumed yes | ⚠️ Not visually verified this session | Not observed | Source only |
| Admin Dashboard | `/admin-dashboard` | Requires admin role | ⚠️ Not verified (no admin credential attempted) | Not observed | Implementation exists (§7) |

## 5. Screenshots

Captured to session scratchpad (not committed to the repository — these are inspection
artifacts, not project source):

1. `01_launch.png` — onboarding welcome screen ("Stronger every rep")
2. `03_click_signin.png` — sign-in form
3. `05_login_network_debug.png` — **Home dashboard**, authenticated as the seeded QA fixture client (`test@12circle.app`)
4. `20_workouts.png` — **Train Hub / Workouts** tab, authenticated

Additional capture attempts for Nutrition/Check-In/Connect returned either a too-early
blank frame or a still-on-login-screen frame due to timing/rate-limit issues explained in
§9 and §14 — those specific files are not cited as evidence of anything.

## 6. Design vs Actual

| Screen | Design Evidence | Actual Rendering | Status | Notes |
|---|---|---|---|---|
| Onboarding | `docs/FINAL_SCREEN_INVENTORY.md` §1 (110 FIT anchors, 105 mapped to routes) | Purple/dark athletic aesthetic, rotating full-bleed photography, "Stronger every rep" / "Push past your limits" copy, Get Started + Sign In | **PARTIAL MATCH** — renders and is on-brand (matches the "Apple Fitness+ / WHOOP" energetic direction referenced in project memory), but this session did not open the FIT reference frame for this exact anchor to do pixel comparison | Visual style plausibly matches direction; not pixel-verified |
| Sign In | Category A/D per `DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` | Clean dark-mode form, Apple/Google OAuth buttons present | **UNABLE TO VERIFY** against a specific FIT anchor | Not cross-referenced to a manifest id this session |
| Home dashboard | — | Greeting header, hero workout image, "12 Circle Score" gamification card, 4 quick-action tiles (Weekly Check-In, Women's Health, AI Coach, Book a Call), My Plan card, 5-tab bottom nav | **RENDERS AND FUNCTIONS** — real data, real score (0 pts today), real assigned-program state | Not cross-referenced to a specific FIT anchor this session |
| Workouts / Train Hub | `DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` maps several FIT ids to workout screens | "This Week" plan list (4 sessions, 45 min each), stats row (streak/this-week/total/done-rate, all showing placeholder `—` or `0`), 6 navigation cards | **RENDERS**; stats row shows uninitialized/placeholder values (`0` streak, `—` for three of four stats) for this fixture account | Could indicate this fixture has no historical completion data, or an incomplete stats binding — **not diagnosed further, per governance (no fixing/investigating)** |
| Nutrition, Check-In, Connect, Profile, Settings, Progress, Community/Events | `docs/SCREEN_DESIGN_GAPS.md` documents 32 anchors at "0/N — design effectively unbuilt" across 18 routes, and 56 more "partial" | **UNABLE TO VERIFY VISUALLY** this session | **UNABLE TO VERIFY** | See §9, §14 |
| Admin / Trust / Guardian / Incidents / Audit / Wearable / Security Center | See §8 | Not opened | **NOT VERIFIED** (Admin) / **NOT IMPLEMENTED** (all others) | Source-code confirmed only |

**I did not treat V5 as proof any screen exists**, and did not compare against imagined
designs — every claim above is either a direct screenshot taken this session or a citation
of an existing repo document (`docs/FINAL_SCREEN_INVENTORY.md`, `docs/SCREEN_DESIGN_GAPS.md`,
`docs/DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md`, `docs/DESIGN_CAPABILITY_GAPS.md`), all present
in the repository before this session began.

## 7. Major Implemented Areas

Confirmed by direct visual capture this session:
- Onboarding / marketing carousel
- Email/password sign-in (+ Apple/Google OAuth buttons, not exercised)
- Authenticated Home dashboard with live QA data, gamification (12 Circle Score), quick actions
- Workouts / Train Hub with an assigned weekly program, stats surface, sub-navigation cards

Confirmed present in source (not opened this session): Nutrition, AI Nutrition/Coach, Check-Ins,
Community/Pods/Events/Challenges/Classes, Messaging, Progress, Coach-side screens (dashboard,
copilot, program builder, client management — 14 "coach product" routes per
`FINAL_SCREEN_INVENTORY.md` §2 category K), Billing/Subscription, Settings, Admin dashboard
(admin-only), Observability (admin-only, coaching-quality analytics — distinct from a
security/audit center).

Per the repo's own authoritative counts (`FINAL_SCREEN_INVENTORY.md`): **148 total product
surfaces**, **91 registered routes** (89 in a release build — 2 QA-only routes are gated out,
consistent with the release-mode gating a prior remediation added), 88 distinct route-building
widgets, 52 modal/sheet surfaces, 27 intake flow steps.

## 8. Major Missing Areas

Checked directly against source (`find lib -iname` for each term — zero results means zero files):

| Area | Status | Evidence |
|---|---|---|
| ADMIN | **PARTIAL** | 3 files exist (`admin_service.dart`, `admin_provider.dart`, `admin_dashboard_screen.dart`), route `/admin-dashboard` registered. Not visually verified (no admin credential used this session) |
| TRUST | **NOT IMPLEMENTED** | Zero files matching `*trust*` |
| AI GUARDIAN | **NOT IMPLEMENTED** | Zero files matching `*guardian*` |
| INCIDENTS | **NOT IMPLEMENTED** | Zero files matching `*incident*` |
| AUDIT CENTER | **NOT IMPLEMENTED** | Zero files matching `*audit*`. A distinct "Observability" screen exists (`/observability`, admin-only) but is scoped to **coaching quality**, not a security/audit log — do not conflate the two |
| WEARABLE INTELLIGENCE | **NOT IMPLEMENTED** | Zero files matching `*wearable*` — consistent with this being documented elsewhere as roadmap-only |
| SECURITY CENTER | **NOT IMPLEMENTED** | Zero files matching `*security_center*` or a `SecurityCenter` class |
| ADVANCED V5 CONTROLS | **NOT IMPLEMENTED / NOT APPLICABLE** | No V5-specific control surface exists in `lib/`; V5 planning artifacts exist only under `docs/` |

Absence is recorded neutrally, per the mission's own instruction — it is not scored as a defect here.

## 9. Runtime Issues

Only what was actually observed this session:

1. **Bare launch (no `--dart-define`) fails at startup with a `StateError`.** Documented in
   §2. This is intended fail-closed behavior per a prior remediation, not a new defect — but
   it does mean a completely "default" launch of the app shows nothing but a crash screen,
   which is worth the product/release team's awareness if not already known.

2. **Repeated automated sign-in against the QA fixture account (`test@12circle.app`) became
   unreliable after the first successful attempt within a ~10-minute window.** The first
   sign-in succeeded cleanly (POST `/auth/v1/token?grant_type=password` → 200, all subsequent
   REST reads → 200). Three subsequent sign-in attempts against the same account, from fresh
   isolated browser instances, resulted in the sign-in button entering its loading state but
   the underlying network request **never being observed to fire or complete** even after
   30–45 second waits. I did not investigate root cause (that would exceed this mission's
   read-only scope), but the most likely explanation is Supabase Auth rate-limiting on
   repeated password-grant attempts for one identity within a short window — which, if true,
   is a security control working as intended, not a defect. I stopped attempting further
   logins once this pattern was clear, to avoid placing more load on the shared QA project's
   auth service. **This is the direct cause of §14's "unable to verify" count.**

3. **Workouts/Train Hub stats row shows `0`/`—` for streak, this-week, total, and done-rate**
   for the signed-in fixture account, even though a weekly program with 4 sessions is
   assigned. This may reflect a genuinely empty history for this fixture identity (most
   likely) or an unbound stats query — **not diagnosed further**, per the no-fixing rule.

No JavaScript console errors were observed on the screens actually reached, aside from
benign WebGL/CanvasKit performance warnings (`GPU stall due to ReadPixels`), which are a
known Flutter-web-on-CanvasKit characteristic, not an application defect.

## 10. Design Gaps

Cited directly from existing repo documents, not newly evaluated:

- `docs/SCREEN_DESIGN_GAPS.md`: of 110 designed ("FIT") anchors, **19 are complete**, **56
  are partial**, and **32 are at 0/N ("design effectively unbuilt")** across 18 routes.
  Declared interactions present: 287 of 600.
- `docs/FINAL_SCREEN_INVENTORY.md`: category breakdown across the 91 routes includes 35
  "DESIGN + IMPLEMENTATION" (complete pairing), 2 "DESIGN + IMPL PARTIAL", 13 "IMPL EXISTS +
  DESIGN MISSING", and smaller categories for aliases, dead routes, redirects/stubs,
  debug/QA-only, admin/vendor, and coach-product routes.
- I did not re-derive or dispute these figures — they are the authoritative, pre-existing
  evidence the mission instructed me to use, and this session's direct observations (§6) are
  consistent with them wherever they overlap (e.g., a rendering, functioning Home and
  Workouts screen against category-A-style "DESIGN + IMPLEMENTATION" expectations).

## 11. V5 Readiness Observation

Stated as observation only — **no readiness determination is made here.**

**Represented in some form in the current mobile app:**
- ADMIN — partial (dashboard screen + provider + service exist; role-gated; not opened this session)
- Observability-style analytics exists, but scoped to coaching quality, not security/audit

**Not represented at all in the current mobile app:**
- TRUST
- AI GUARDIAN
- INCIDENTS
- AUDIT CENTER (as a security/audit surface, distinct from Observability)
- WEARABLE INTELLIGENCE
- SECURITY CENTER
- Any V5-specific control surface

## 12. Security / Data Observations

Observations from this run only — **no remediation performed or recommended here.**

- The app initialized against the QA Supabase project (`eyqtldjqpgpljlqvpowh`) using the
  committed `dart_defines/qa.json` anon key, exactly as documented in the repo.
- Signing in as the seeded QA fixture client (`test@12circle.app`) returned real profile,
  score, notification, workout-session, program-assignment, and nutrition-log data for that
  fixture's own user id (`5470a95f-bcae-4e01-b2be-7c16964fa432`) — consistent with normal,
  expected RLS-scoped behavior (a user reading their own rows), not a leak of another user's
  data.
- The signed-in fixture's display name rendered as **"Jordan"**, not "Amara Osei" as named in
  the mission's "currently established design/test identities" note. **I am reporting this
  discrepancy rather than treating "Jordan" as "Amara Osei" or vice versa** — the mission was
  explicit that those named identities should be used "only if the existing application
  already uses those configured records," and this session found the QA fixture actually
  configured under those credentials to be named Jordan, not Amara. No record was inserted,
  renamed, or altered to investigate or correct this discrepancy.
- The apparent auth rate-limiting behavior in §9.2 is, if confirmed, a positive security
  control (protecting against credential-stuffing / brute-force), not a gap.
- No sensitive data beyond what's necessary to identify the screen state is included above
  (no tokens, no raw JWTs, no other users' data were captured or are reproduced here).

## 13. Screens Visually Verified

**4** distinct screens/states, via direct screenshot this session:
1. Onboarding / welcome carousel
2. Sign-in form
3. Home dashboard (authenticated, live QA data)
4. Workouts / Train Hub (authenticated, live QA data)

## 14. Screens Unable To Verify

**87** of the 91 registered routes were not opened this session (91 total − 4 verified).
Reason: after one successful authenticated session, three subsequent sign-in attempts against
the same QA fixture account did not complete (auth request never observed firing within
30–45s per attempt — see §9.2), most likely due to Supabase Auth rate-limiting on repeated
password-grant attempts for one identity in a short window. Rather than continue retrying
against a live, shared QA project — which risks extending any rate-limit window and adding
unnecessary load — I stopped and am reporting the gap honestly. Nutrition, Check-In, Connect,
Profile, Settings, Progress, Community, Coach-side screens, and Admin/Observability are all in
this "unable to verify visually" set; their **existence in source** is separately confirmed in
§7–§8 by direct code inspection, which is clearly distinguished above from visual verification.

---

## Final adversarial check (Step 12)

1. Did I accidentally modify source? **No** — `git diff --stat` and `git diff --name-only` are both empty; only `.dart_tool/` and `build/` (gitignored, not inspected for changes) were touched by the Flutter toolchain.
2. Did Flutter modify any tracked file? **No** — confirmed via `git status`/`git diff` after the run.
3. Did I alter dependencies? **No** — only `flutter pub get --dry-run` was run; it reported "No dependencies would change" and made no writes.
4. Did I write to a database? **No** — all Supabase calls observed were `GET` reads and the one `POST /auth/v1/token` sign-in call, which is a normal read-only-from-the-inspector's-perspective auth action, not a data mutation. No `INSERT`/`UPDATE`/`DELETE` was issued by anything I ran.
5. Did I alter shared QA? **No writes.** The only QA-affecting action was signing in as an existing seeded fixture account four times, which is an auth event, not a data mutation; I did not seed, create, or modify any record.
6. Did I create test data? **No.**
7. Did I invent any screen? **No** — every screen named in §4/§6/§7 is either a live screenshot or is cited directly from an existing `docs/*.md` file already in the repository.
8. Did I claim a design exists when it does not? **No** — §6 and §10 clearly separate "rendered and observed," "implementation exists in source (not opened)," and "unable to verify," and cite the pre-existing design-gap documents rather than asserting completeness.
9. Did I treat V5 requirements as implemented features? **No** — §11 explicitly lists V5 areas as "not represented" where that's what source inspection showed.
10. Did I confuse route count with screen count? **No** — §7 reports both the 91-route and 148-surface figures separately, as the repo's own `FINAL_SCREEN_INVENTORY.md` distinguishes them, and does not treat them as interchangeable.
11. Did I expose unnecessary sensitive client information? **No** — only a first name ("Jordan") and non-sensitive UI state (score, program names, tab structure) are reported; no raw tokens, emails-as-secrets, or other users' data appear above.
12. Did I accidentally begin V5/Admin implementation? **No** — no code was written or modified; the Admin screen was not even opened (no admin credential was used).

No correction to this report was required as a result of this check.

## Final Repository Verification (Step 13)

```
$ git status
On branch reconcile/12circle-integrated
Untracked files:
	docs/QA_COMPLETION_REPORT_2026-09-27.md
	docs/QA_FINAL_RECONCILIATION_REPORT.md
	docs/QA_TO_V5_TRANSITION_RECONCILIATION_2026-09-27.md
	docs/RECONCILIATION_LOCAL_CLOUD_GITHUB.md
	docs/V5_D1_SECURITY_FOUNDATION_AUTHORIZATION_ANALYSIS_2026-09-27.md
	docs/V5_DECISION_RESOLUTION_2026-09-27.md
	docs/V5_DESIGN_AUTHORITY_RECONCILIATION_2026-09-27.md
	docs/V5_FINAL_DESIGN_AUTHORITY_RECONCILIATION_2026-09-27.md
	docs/V5_IMPACT_ANALYSIS_2026-09-27.md
	docs/V5_IMPLEMENTATION_READINESS_GATE_2026-09-27.md
	docs/V5_SECURITY_FOUNDATION_OWNER_DECISION_AND_IMPLEMENTATION_READINESS.md
	supabase/tests/security/d09-assessment-access.mjs
nothing added to commit but untracked files present (use "git add" to track)

$ git diff --stat
(empty)

$ git diff --name-only
(empty)

$ git rev-parse HEAD
07f5bfb9115f74b3c3e262e1d0d3bc4607ffe99f
```

**HEAD unchanged. Zero tracked-file modifications. All untracked files pre-date or arose
independently of this session's actions (concurrent Cowork activity) and were neither
created nor touched by this inspection.**

This report file itself (`MOBILE_VISUAL_BASELINE_REPORT_2026-09-27.md`) is the one new file
this session adds, per the mission's own Step 11 instruction to create it.
