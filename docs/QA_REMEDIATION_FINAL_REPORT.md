# 12Circle Fitness — QA Remediation Final Report

**Branch** `chore/qa-environments-secure-ai-backend`
**Head at close** `e2f8d8d`
**Baseline at entry** 1,597 pass / 9 skipped / 0 analyzer errors
**At close** **1,612 pass / 9 skipped / 0 analyzer errors**

> **On the structure.** The directive required a thirteen-section report but the section
> list is not recorded anywhere in the repository, and this session did not retain it
> verbatim. The headings below are a reconstruction covering every substantive
> requirement that *was* retained. Flagged rather than presented as if it were the
> original.

---

## 1 · Scope of this wave

Remediation, not discovery: take the findings already on the register, fix what is
executable under governance, and leave what is not with a reason. Security and privacy
first. New findings were recorded when a remediation trace turned them up, but no new
discovery programme was opened.

---

## 2 · What was fixed

| ID | Area | Change | Proof |
|---|---|---|---|
| **SEC-VIDEO-1** | Storage privacy | Coach video responses persisted a **permanent unauthenticated URL** to a video of a coach discussing a named client. Now stores the object path, to be signed at render time. | VIDEO-G1, **4/4 mutations killed** |
| **ERR-2** | Information disclosure | **38** sites across **26 files** interpolated a raw exception into user-facing copy. All closed. | ERR-G2, **5/5 killed** |
| **LIFE-G1** | Stability | **54** `setState`-after-`await` sites with no `mounted` guard — "setState() called after dispose()" for any user who leaves a slow screen. All guarded. | LIFE-G1, **4/4 killed** |
| **WO-G1** | Data minimisation | Two tables written and never read, both announced to a user with a tap promise the app cannot keep. Ratcheted; the defects themselves are owner decisions. | WO-G1, **4/4 killed** |

Four commits: `8f9b56a`, `c993594`, `db910f0`, `e2f8d8d`.

---

## 3 · Corrections to the existing record

These matter more than the fixes, because each was a **passing or closed** item that was
not what it claimed.

1. **SEC-PHI-2's residual said "five other sites".** The real number was **38**, and its
   characterisation was wrong twice over: it listed the offenders as "all on non-PHI
   coach screens" when `womens_health_screen.dart` was among them, and described the two
   admin sites as *parsing rather than displaying* when the admin error card did **both**.
   Its `denied` branch exists precisely because non-admins reach that screen — so every
   error that was not `42501` printed raw Postgres text to exactly that audience.

2. **OD-25's in-code reason was stale on two of three clauses.** It left the check-in
   board's `Record` button inert citing *"no capture path, no upload, no player."* The
   capture (`ImagePicker().pickVideo`) and upload both existed, in a screen reachable from
   `client_detail_screen.dart:359` that even accepts the `checkinId` that board would
   pass. Only *no player* held. **The outcome survives, the reason did not** — wiring the
   button would have added a second entrance to a dead end. Comment corrected in place.

3. **`coach_video_responses` and `workout_feedback` are write-only.** Both notify a user
   to tap and view something no screen renders.

---

## 4 · New findings, recorded not silently decided

| ID | Finding | Why it is not QA's call |
|---|---|---|
| **OD-57** | Video responses are write-only; client is told *"Tap to watch"* and no player exists | Building a player is a feature; removing the feature is a product decision |
| **OD-58** | `transformation_photo_urls` sit on the public bucket | Marketplace marketing photos, plausibly intended public — but the subjects are identifiable clients, so consent is the owner's question |
| **OD-59** | `workout_feedback` is write-only; coach is told *"tap to view"* | Same shape as OD-57 |

---

## 5 · What every guard had to survive

No detector's output was accepted before it was shown capable of finding a planted or
known instance. Five would have produced a wrong answer:

- A line-based `mounted` sweep said **135**; brace-scoping gave **54**. Its "past an
  await" flag leaked out of one method into the `onTap:` handlers of the `build` below.
- Its first clean run's last hit was `active_workout_screen`'s **own comment** describing
  this bug — a guard fooled by prose about the defect it enforces.
- An exception sweep matching `${e.key}` reported **59** for **38** real sites.
- The write-only sweep reported **4**; two were reads it could not see (a PostgREST
  embedded resource, a dynamic table name). Separately the notification type
  `'type': 'workout_feedback'` made a genuinely dead table read as live, which would have
  **hidden** OD-59 behind a passing test.
- The dispose sweep found **1** controller field in the whole app — it required an
  explicit type where this codebase infers. Corrected, it found 89.

And mutation testing found a flaw in a guard I had already called done: **ERR-G2's
allowlist was file-granular**, so planting a leak in a listed file **SURVIVED** — and two
of the five listed files are PHI-adjacent, including `client_detail_screen.dart`. It is
now line-granular and asserts each exemption still occurs.

---

## 6 · Not remediated, with reasons

| Item | Status | Reason |
|---|---|---|
| 101 `catch` → bare default sites | **OD-8, owner** | Converting them needs UI error states that mostly do not exist. The attempt to isolate the provable subset returned 0, and its two candidates were false. Stated as *not found by this method*, not *none exist*. |
| SEC-PHI-1 | **OWNER** | Another workstream's finding; wide `102` arms |
| SEC-PHI-3 | **BLOCKED (ordering)** | Dart repoint cannot precede the RPC's migration |
| SEC-PHI-4 | **OWNER** | Remediation is legal copy or new controls |
| SEC-PHI-AUDIT, N-07 | **BLOCKED (OD-56)** | Migration number + sign-off |
| SEC-VOICE-1 (b) | **BLOCKED** | Migration number; read policy is an owner decision |
| Device runtime verification | **BLOCKED** | Environmental |

**One blocker did shrink.** With voice signing at render time and the video path having no
reader, **no `coach-media` read in the app breaks when the bucket is privatised.** Only
the marketplace photos (OD-58) remain in question.

---

## 7 · Governance

No migration was written, numbered or applied. `MASTER_REMEDIATION_WAVES.md` reserves
**132+** "assigned at wave entry, never before", and that was respected. Two proposals
remain **AUTHORED and unnumbered**.

The other workstream's files — `N07_IMPLEMENTATION_STATUS.md`,
`proposed/N07_assessment_access.sql`, `supabase/tests/security/d09-assessment-access.mjs`,
`FINAL_NEW_SCREEN_DESIGN_COMMISSION.md` — were **read as evidence and not modified**.
`d09-assessment-access.mjs` remains untracked; it is theirs to commit.

New IDs were checked against the registers before assignment: `SEC-VIDEO-1`, `OD-57`,
`OD-58`, `OD-59`. No existing ID was reused. Where my sweep rediscovered findings QA
Workstream I already registers (`I-CHK-01`, `I-LEG-03`), **no competing guard was added**.

All commits used explicit paths.

---

## 8 · An error of mine, uncorrected on purpose

A mechanical second pass in this session stripped trailing colons app-wide and damaged
unrelated copy — UI labels, package descriptions, and **`privacy_policy_screen.dart`**,
which is legal text under SEC-PHI-4's owner decision. It was caught on review, and `lib/`
was reset to `HEAD` and the work redone from an explicit, exact-match table with
per-entry count verification. Nothing from that pass reached a commit. Recorded because
the near-miss is the point: a regex confident enough to rewrite 28 lines was wrong about
half of them.

---

## 9 · Verification standard

Every fix carries a guard, every guard was mutation-tested, and results are reported as
KILLED / SURVIVED / **INVALID** — a mutation that failed to compile, or whose own script
failed, is not a kill. Two INVALID results were caught and redone this session.

`LOCALLY_VERIFIED ≠ RUNTIME_VERIFIED` holds: the suite and analyzer are local. Live
evidence in the ledger came from **read-only** probing of the QA project only.

---

## 10 · What a reviewer should check first

1. **ERR-G2's allowlist** — five exemptions, each a named code fragment. It is the piece
   most likely to be widened carelessly.
2. **The 13 nested `mounted` guards** — `&& mounted` and `if (mounted)` were chosen over
   early `return` where code after the call must still run. Worth a second pair of eyes.
3. **OD-57 / OD-59** — two features that collect data about people and show it to nobody.

---

## 11 · Test and analyzer state

```
1,612 pass · 9 skipped · 0 analyzer errors
```

The 9 skips are pre-existing and unchanged. The 312 analyzer infos are pre-existing
lint advisories, none of them errors.

---

## 12 · Honest limits

- No claim of HIPAA compliance is made anywhere in this work.
- The masking-tail negative is a limit of the method used, not a proof of absence.
- No runtime/device verification was performed this wave.
- Guards assert source shape where the layer beneath is not injectable; those assertions
  are labelled `[SOURCE]` and are worth what a source assertion is worth.

---

## 13 · Verdict

The executable backlog reachable under current governance is exhausted: everything
remaining is an **owner decision**, a **migration-numbering block**, or an
**environmental block**, each named in §6 with its reason. Four defect classes were
closed with mutation-tested guards, and three closed records were corrected to match what
the code actually does.

**REMEDIATION EXECUTABLY EXHAUSTED**
