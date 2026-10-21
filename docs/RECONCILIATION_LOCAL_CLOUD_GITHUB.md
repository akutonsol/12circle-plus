# 12CIRCLE FITNESS — LOCAL ↔ CLOUD ↔ GITHUB RECONCILIATION REPORT

**READ-ONLY FORENSIC RECONCILIATION. NOTHING WAS MODIFIED, MERGED, PUSHED, PULLED,
RESET, REBASED OR DELETED.**

> **This file is UNCOMMITTED and untracked.** The phase forbids committing and forbids
> modifying documentation, so it is written as a new artifact and left unstaged. No
> existing document was touched.

**Method note:** no `git fetch` was performed. GitHub state was read with `git ls-remote`
(reads refs, downloads nothing, updates no local ref) and the GitHub REST API via `gh`
(touches the local repository not at all). Cloud objects were **never** downloaded into
`.git`.

---

## A · Repository identity

| | |
|---|---|
| Root | `/Users/dmac/Documents/projects/12circle-fitness` |
| Name | `12circle-fitness` (`package.json`) |
| Origin | `https://github.com/akutonsol/12circlefitness.git` |
| Current branch | `chore/qa-environments-secure-ai-backend` |
| HEAD | `fd7286212361cdc2dfdb110fdf9640fde2d4a20e` |

Confirmed, not assumed.

---

## B · Local state

| | |
|---|---|
| Working tree | **clean** — no staged, no unstaged changes |
| Untracked | **1 file** — `supabase/tests/security/d09-assessment-access.mjs` |
| Local branches | `chore/qa-environments-secure-ai-backend` → `fd72862` (**ahead 135**), `main` → `9dc7515` (in sync) |
| Remote-tracking | `origin/chore/...` → `cafcfe9`, `origin/main` → `9dc7515` |
| Ref for the Cloud branch | **NONE** |
| Cloud commits present locally | **1 of 21** (only the shared base `cafcfe9`) |

---

## C · Cloud state

Branch `claude/dreamy-ptolemy-3sk1vz`, tip **`211da3fa60b1fbd254f87ee12f3d743c14a0a3f1`**.

> **Correction to the brief:** it gave the tip as `211da3f60b1fbd254f87ee12f3d743c14a0a3f1`
> — **39 characters, malformed**. The real SHA is `211da3fa60b1…`. Verified via
> `ls-remote` and the compare API.

All 20 Cloud commits from the brief's list were verified present on that branch;
**20 of 21 listed SHAs are absent from the local object store**.

---

## D · GitHub state (authoritative, from `ls-remote`)

| GitHub branch | SHA |
|---|---|
| `chore/qa-environments-secure-ai-backend` | `cafcfe9ef97eedd00f0d3ba53466375a664d1656` |
| `claude/dreamy-ptolemy-3sk1vz` | `211da3fa60b1fbd254f87ee12f3d743c14a0a3f1` |
| `main` | `9dc751537baa8b0e1027a90f7a6d331188d3ae8e` |

**Cloud and GitHub are NOT the same thing, and were verified separately.** The Cloud work
lives on its **own branch**. GitHub's `chore/` branch — the branch I am on — is still at
`cafcfe9`. My remote-tracking ref is **not stale**; it is correct.

---

## E · Branch topology · F · Common ancestor

```
                       cafcfe9ef97e   ← merge base, AND the current GitHub
                            │            tip of chore/qa-environments-secure-ai-backend
                            │
        ┌───────────────────┴───────────────────┐
        │                                       │
   LOCAL / DESKTOP                         CLOUD QA
   135 commits, UNPUSHED                   20 commits, PUSHED
   → fd72862                               → 211da3fa
   (chore/qa-environments-                 (claude/dreamy-ptolemy-3sk1vz)
    secure-ai-backend)                          │
                                                └── visible on GitHub
```

Merge base independently confirmed by the compare API: `cafcfe9…`, Cloud **20 ahead /
0 behind**. Neither side has been merged into the other. **Nothing has been overwritten
on either side.**

---

## G · Local-only commits

**135**, not 4. The brief's list of four is **stale** — it predates nine further local
commits made after that report was written.

The four named SHAs all exist locally, are reachable from the local branch, and all
descend from `cafcfe9`, forming one chain:

```
9fb7260 → a2bfada → a857993 → 7847c4e        (…then 0088089, c838996, 0fc5f5e,
                                               e591528, c8db15e, fd72862, …)
```

| SHA | Subject | Files |
|---|---|---|
| `9fb7260` | docs(security): security/HIPAA exhaustion audit — discovery only | 1 |
| `a2bfada` | fix(security): SEC-VOICE-2 — store the object path for coach voice notes | 3 |
| `a857993` | fix(privacy): AIMEM — failed deletion of a health fact no longer silent | 3 |
| `7847c4e` | docs(security): remediation report, SEC-PHI-1 proposal, two retractions | 3 |

None is represented on Cloud under a different SHA.

---

## H · Cloud-only commits

20, `bde7970` … `211da3f`. Substance: a `QAX-*` exhaustion programme that **fixed**
defects (COR-01…08, ERR-01/02, SES-01, SEC-08/09/10), added `supabase/tests/qa_exhaustion/`
fixtures and probes, a guarded-write scanner, widget failure tests, and
`docs/QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md`.

**51 files changed, 38 of them Cloud-only.**

## I · GitHub-only commits

**None.** GitHub holds exactly the Cloud branch plus an unchanged `chore/` tip and an
in-sync `main`.

---

## J · Uncommitted local work

| Path | Status | Type | Source | Tracked | Project work | Generated | Safe to preserve | Manual reconciliation |
|---|---|---|---|---|---|---|---|---|
| `supabase/tests/security/d09-assessment-access.mjs` | `??` untracked | security test, 174 lines | another workstream | **No** | **Yes** | No | **MUST preserve** | **Yes** |

**⚠ HIGHEST-RISK ITEM IN THE ENTIRE RECONCILIATION.** Verified **404 on all three GitHub
refs** (`claude/dreamy-ptolemy-3sk1vz`, `cafcfe9`, `main`) and `git log --all` shows it
was **never committed in any local branch**. It exists in exactly one place: this working
tree. Any `git clean`, fresh clone, or worktree reset destroys it permanently.

---

## K · File-level overlaps

**Local 328 files · Cloud 51 files · overlap 13.**

| File | Cloud hunks | Local hunks | Verdict |
|---|---|---|---|
| `dashboard/presentation/coach_dashboard_screen.dart` | 2 | 20 | **SAME LINES — MANUAL** |
| `goals/presentation/goals_screen.dart` | 3 | 3 | **SAME LINES — MANUAL** |
| `home/presentation/home_screen.dart` | 1 | 18 | **SAME LINES — MANUAL** |
| `nutrition/presentation/meals_dashboard_screen.dart` | 6 | 34 | **SAME LINES — MANUAL** |
| `womens_health/presentation/womens_health_screen.dart` | 5 | 3 | **SAME LINES — MANUAL** |
| `dashboard/presentation/client_detail_screen.dart` | 2 | 4 | adjacent (≤6 lines) — review |
| `profile/presentation/personal_info_screen.dart` | 3 | 3 | adjacent — review |
| `progress/presentation/progress_screen.dart` | 10 | 14 | adjacent — review |
| `test/unit/presentation_drift_guard_test.dart` | 2 | 6 | adjacent — review |
| `checkins/data/weekly_checkin_service.dart` | 1 | 4 | disjoint — likely coexist |
| `coach/domain/coach_ecosystem_provider.dart` | 4 | 3 | disjoint |
| `settings/presentation/terms_of_service_screen.dart` | 1 | 1 | disjoint |
| `workout/domain/workout_provider.dart` | 2 | 1 | disjoint |

---

## L · Duplicate work — the central finding

**Two independent workstreams converged on the same defects. Cloud FIXED what Local
DOCUMENTED.** Local was under a discovery-only instruction, so this is not wasted work —
but it is duplicated analysis.

| Local finding | Cloud commit | Classification |
|---|---|---|
| **CORR-1** — `CycleService` silent success on null uid | `b0954f5` QAX-ERR-01 — adds `_requireUid()` that **throws** instead of returning | **FUNCTIONAL DUPLICATE — Cloud fixed it** |
| **CORR-3** — guarded writes; gender deselect discarded | `fdbd67b` QAX-COR-01 — extracts `buildPersonalInfoPayload()`; `gender` unconditional, `phone` → `orNull(phone)`, height/weight/goal unconditional | **FUNCTIONAL DUPLICATE — Cloud fixed it** |
| **SEC-PHI-4** — Terms claims in-app deletion | `810430d` UIX-2 — Terms corrected + guard | **FUNCTIONAL DUPLICATE** |
| **CORR-4** — optimistic/unsurfaced write failures | `fa593a7`, `50c5437`, `4df390b` | **PARTIAL DUPLICATE** |

**Striking convergence:** my validated guarded-write set was exactly 5 fields — `gender`,
`phone`, `height_cm`, `weight_kg`, `weight_goal_kg` — after I cut an initial 19 down by
tracing UI paths. **Cloud's fix changes exactly those five** and deliberately leaves
`fitness_goal`, `activity_level`, `training_location`, `nutrition_goal` and
`date_of_birth` still guarded — matching my own conclusion that those have no clear
affordance. Two independent analyses, same answer.

### Local findings NOT covered by Cloud (unique, still open)

- **CORR-8** — `saveSettings` has **no callers**; cycle predictions run on hardcoded
  28/5 defaults. Cloud's patch makes that unreachable method *throw*, but does not give
  it a caller. **The defect survives Cloud's fix.**
- **CORR-9** — corrections leave no trace: `user_profiles.updated_at` does not move
  (live-verified); `set_updated_at` is attached to seven tables including `coach_notes`.
- **SEC-PHI-9 / SEC-PHI-10** — coach retains progress-photo access after revocation
  (live-verified), plus `score_events`.
- **SEC-VOICE-2**, **SEC-PHI-1**, **SEC-PHI-6/7**, **SAFE-1**, **A11Y-1**, **OD-57…62**.

---

## M · Actual conflicts

### M1 · Five files where both sides edited the same lines
Listed in §K. Requires human reconciliation.

### M2 · My shrinking-allowlist guards will FAIL against Cloud's code — **by design**

`apps/mobile/test/unit/correction_rights_guard_test.dart` (CORR-G1) asserts the defects
**still exist**, so it fails the moment they are fixed. Verified: Cloud **removed all
four anchors** it asserts:

| Anchor CORR-G1 requires | Cloud |
|---|---|
| `if (_gender != null) payload['gender']` | **REMOVED** |
| `if (_phoneCtrl.text.trim().isNotEmpty)` | **REMOVED** |
| `Future<void> endCurrentPeriod` | **REMOVED** (now `Future<bool>`) |
| `if (uid == null) return;` | **REMOVED** |

**On merge these tests must be DELETED, not repaired.** Deleting the entry is the
documented last step of closing the finding. Anyone "fixing the failing test" would
re-assert a defect that no longer exists.

### M3 · ERR-G2 allowlist needs two additions
Cloud adds two `(e) => '$e'` list-stringification lines — `baseline_photo_replace.dart`
and `womens_health_screen.dart`. These are ERR-G2's **known false-positive class** but
are not in its line-granular `permitted` map, so ERR-G2 **will fail on merge** until they
are listed.

### M4 · LIFE-G1 — **UNKNOWN until merged**
Cloud adds 6 `setState` lines in files LIFE-G1 sweeps. Whether any is post-`await` and
unguarded cannot be determined from the patch alone; the brace-scoped sweep must be re-run
after integration.

---

## N · QA report differences

| Report | Local | Cloud | GitHub | Newest | Status |
|---|---|---|---|---|---|
| `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md` | ✗ | **✓ added (863 lines)** | ✓ (cloud branch) | Cloud | **CLOUD ONLY** |
| `QA_SECURITY_HIPAA_EXHAUSTION_REPORT.md` | ✓ | ✗ | ✗ | Local | **LOCAL ONLY** |
| `QA_SECURITY_HIPAA_REMEDIATION_REPORT.md` | ✓ | ✗ | ✗ | Local | **LOCAL ONLY** |
| `QA_REMEDIATION_FINAL_REPORT.md` | ✓ | ✗ | ✗ | Local | **LOCAL ONLY** |
| `QA_MASTER_FINDINGS_LEDGER.md` | ✓ | ✗ | ✗ | Local | **LOCAL ONLY** |
| `QA_CORRECTION_RIGHTS_EXHAUSTION_REPORT.md` | ✓ | ✗ | ✗ | Local | **LOCAL ONLY** |
| `SECURITY_LEDGER_PHI.md` | ✓ modified | ✗ | base only | Local | **LOCAL ONLY** |
| `MASTER_REMEDIATION_REGISTRY.md` | ✓ modified | **✓ modified (+100)** | both | — | **CONFLICT / OVERLAP** |
| `REMEDIATION_PROGRESS.md` | ? | **✓ modified (+2)** | Cloud | Cloud | **CLOUD ONLY** |
| `N07_IMPLEMENTATION_STATUS.md` | ✓ (base) | ✗ | base | — | **IDENTICAL** |
| `FINAL_NEW_SCREEN_DESIGN_COMMISSION.md` | ✓ (base) | ✗ | base | — | **IDENTICAL** |

Both sides modified `MASTER_REMEDIATION_REGISTRY.md` — additive in both cases
(Cloud +100 lines, §7.24), so it should merge, but needs review for section collisions.

---

## O · Security / HIPAA differences

Cloud adds a live-probe harness Local never had: `supabase/tests/qa_exhaustion/` with
`probes.sql`, `fixtures.sql`, `run.sh` and nine `fixsim/QAX-SEC-*.sql` simulations —
including **QAX-SEC-08 team-lead** and **QAX-SEC-09 event-host PHI reads**, which are
precisely the two `102` policy arms Local recorded as **NOT TESTABLE** for want of
fixtures.

**This is the most valuable Cloud asset for Local's open findings.** It may unblock
SEC-PHI-1 verification without `QA_SERVICE`.

Local uniquely holds: `SECURITY_LEDGER_PHI.md`, four `docs/proposed/*.sql` governed
migration proposals, and the live-verified SEC-PHI-9 revocation finding.

---

## P · Migration differences — **CLEAN**

| | |
|---|---|
| Cloud changes under `supabase/migrations/` | **NONE** |
| Local changes under `supabase/migrations/` | **NONE** |
| Migration-number conflicts | **NONE** |
| Migrations applied by either side | **NONE** |

**Both workstreams independently respected the `132+` wave-entry rule.** Local added four
**unnumbered** proposals under `docs/proposed/`: `N07_assessment_access.sql`,
`SEC_VOICE_1_coach_media_private.sql`, `SEC_PHI_1_roster_attendee_views.sql`,
`SEC_PHI_9_progress_photo_revocation.sql`. Cloud added none. No collision.

---

## Q · d09 collision

**There is no collision — there is an orphan.** `d09-assessment-access.mjs` is absent from
all three GitHub refs and from every local commit. It is untracked, unbacked and unique.
Not a conflict; a **preservation risk**.

## R · Finding-ID collisions — **NONE**

Namespaces are disjoint: Cloud coined `QAX-*` (60 IDs); Local coined `CORR-*`, `SEC-PHI-*`,
`SEC-VOICE-*`, `SEC-MEDIA-*`, `SAFE-*`, `A11Y-*`, `OD-57…62`. **Cloud assigned no `OD-*`
numbers**, so the OD sequence did not fork.

The 20 IDs appearing on both sides (`F-01…F-22`, `F-J-01/07/17`, `I-CHK-01`, `I-COM-01`,
`ERR-2/3`, `I-WMH-01`, `I-WRK-01/02`) are **inherited from the common base** — both sides
citing the same historical findings. Shared vocabulary, not duplicate assignment.

## S · Owner-decision collisions — **NONE**

No `OD-*` was issued by Cloud. Local's `OD-57…OD-62` stand unopposed.

---

## T · Risk assessment

| Risk | Severity | Note |
|---|---|---|
| `d09-assessment-access.mjs` lost to a clean/clone | **CRITICAL** | exists in exactly one place |
| 135 local commits exist only on this disk | **HIGH** | unpushed; no backup |
| 5 same-line file conflicts | **MEDIUM** | manual merge |
| CORR-G1 fails after merge (by design) | **MEDIUM** | must be *deleted*, not repaired |
| ERR-G2 fails after merge | **LOW** | add 2 allowlist entries |
| LIFE-G1 post-merge state | **UNKNOWN** | re-run required |
| Migration conflict | **NONE** | neither side touched migrations |
| ID collision | **NONE** | disjoint namespaces |
| **Local disk at ~288 MiB, 99 %** | **HIGH** | a merge + test run may not fit |

---

## U · Recommended synchronization plan — **NOT EXECUTED**

Preserves both sides. Nothing overwritten. Nothing deleted.

1. **Back up `d09-assessment-access.mjs` outside the repo, before anything else.**
   It is unbacked and unique.
2. **Resolve the disk problem first.** `df` shows 245 GB total / 18 GB used / 99 % full —
   ~211 GB unaccounted — and `tmutil` shows a staged macOS update snapshot
   (`com.apple.os.update-MSUPrepareUpdate`). This repo's caches are only 362 MB. A merge
   plus a full test run will not fit at 288 MiB.
3. **Push the local branch to a new remote name** so 135 commits stop being single-copy —
   e.g. `chore/qa-desktop-backup`. Publishing only; it overwrites nothing.
4. **Create a reconciliation branch from the common ancestor** `cafcfe9`, then merge
   Cloud first (20 commits, smaller), then Local (135), resolving the 5 same-line files
   by hand.
5. **On merge, expect and correctly handle three guard outcomes:** delete CORR-G1's four
   fixed-defect assertions; add two entries to ERR-G2's `permitted`; re-run LIFE-G1's
   brace-scoped sweep.
6. **Reconcile `MASTER_REMEDIATION_REGISTRY.md`** — additive on both sides; confirm no
   section-number clash with Cloud's §7.24.
7. **Adopt Cloud's `supabase/tests/qa_exhaustion/` harness** and re-test Local's
   NOT-TESTABLE items, starting with SEC-PHI-1's team-lead / event-host arms.

**Explicitly not recommended:** force push, reset, cherry-pick, deleting either side's
commits, or overwriting local files.

---

## V · Requires human approval

1. Any merge or push (all of §U steps 3–4).
2. Resolving the 5 same-line conflicts.
3. Clearing the staged macOS update / APFS snapshots — a system action on the owner's
   machine.
4. Whether Cloud's `QAX-*` fixes supersede Local's corresponding open findings, or both
   should be recorded.

## W · Safe for automated reconciliation (after approval)

- The 38 Cloud-only files (no local counterpart).
- The ~315 local-only files (no cloud counterpart).
- The 4 disjoint-hunk files.
- `docs/proposed/*.sql` — Local-only, additive, no migration numbers.

## X · Must remain untouched

- `supabase/tests/security/d09-assessment-access.mjs` — another workstream's, unbacked.
- `supabase/migrations/**` — neither side changed it; do not renumber.
- Worktree `/private/tmp/12circle-wrk02-negative-control` @ `70a647b`.
- `main` on both sides — already identical.
- Cloud's 20 commits and Local's 135 — **preserve both in full.**

---

## FINAL STATUS

### **DIVERGED — RECONCILIATION REQUIRED**

Both sides are intact and neither has been damaged. They diverged cleanly from
`cafcfe9`: **Local 135 commits (unpushed), Cloud 20 commits (pushed to its own branch)**,
merge base verified independently. Only 13 of 328 local files overlap Cloud, 5 of them on
the same lines. There are **no migration conflicts and no finding-ID collisions.**

The reconciliation is tractable, but it is **not yet safe to execute**: `d09-assessment-access.mjs`
is unbacked and unique, 135 commits exist only on this disk, and free disk is at 288 MiB —
below what a merge plus test run requires. Steps §U.1–U.2 must precede any integration.

**Nothing in this phase was modified, merged, pushed, pulled, reset, rebased or deleted.**
