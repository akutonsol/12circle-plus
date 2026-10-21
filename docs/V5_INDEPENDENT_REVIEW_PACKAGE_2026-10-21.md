# Independent review package — V5 autonomous phase, 2026-10-21

**Purpose.** Everything a reviewer who is *not* this session needs in order to check the work without
re-deriving it. **This phase's verifier was the same model in the same session as the implementer.
That is identity separation enforced by the coordinator, NOT independent human review, and must not
be described as such.**

## 1 · Baseline

* Branch `feat/v5-autonomous-team` · HEAD **`08b354391664f638e0c2fc6b7c20f18f4fb3e4b1`**
* Ahead 11 / behind 0 · **0 staged** · no stash · no in-progress git operation
* **Nothing committed, nothing pushed.** All work is in the working tree.

## 2 · Diff to review (12 files)

| File | Change | Note for the reviewer |
|---|---|---|
| `scripts/guard-protected-paths.mjs` | **new**, ~470 lines | **Untracked, so `git diff` is EMPTY for it.** A diff-based check on this file is vacuous — review the whole file. |
| `scripts/protected-paths.json` | **new**, 28 lines | 11 roots, `exceptions: []` |
| `.skills-agent/decisions.json` | **new**, 64 lines | Both decisions `proposed`, `owner: null`, `record: null` |
| `docs/V5_AUTONOMOUS_PHASE_2026-10-21_FINDINGS.md` | **new** | Analysis and requests only; decides nothing |
| `docs/V5_INDEPENDENT_REVIEW_PACKAGE_2026-10-21.md` | **new** | This file |
| `docs/V5_CONSOLIDATED_DECISION_PACKET_2026-10-21.md` | **new** | All blockers, deduplicated and prioritised. Decides nothing. |
| `scripts/skills-agent-coordinator.mjs` | +~301/−6 | Only 6 removals; `block` command and `blockRefusalReason()` are the additions |
| `.skills-agent/tasks.json` | **+679/−0** | **Additions only.** All 24 pre-existing task rows byte-identical. An earlier edit re-encoded `\uXXXX` escapes in pre-existing rows; that was caught and reverted by textual splice. Worth re-checking. |
| `docs/AUTONOMOUS_TEAM_OPERATING_MODEL.md` | +~256/−0 | Guard self-test, `block`, and Bash sections |
| `.claude/settings.json` | +13/−0 | **Hook only.** `permissions.allow` must hash identical to baseline; no `permissions.deny` |
| `package.json` | +5/−1 | `flow`, `flow:validate`, `flow:selftest`, `guard:selftest`; **0 dependency changes** |

## 3 · Claims requiring verification

1. **The guard's 60-assertion self-test is not inert.** Ten mutations were each shown to fail it.
   Re-derive by breaking the guard in a **copy** and confirming the suite notices. Four of these
   mutations initially passed unnoticed and the suite was fixed; the reviewer should confirm the fixes
   rather than trust the table.
2. **Four formerly-green self-test defects are fixed:** the self-referential root loop (deleting
   `docs/adr` from the config deleted its own assertion — 51 pass before, 50 pass after, green both
   times), the G-3 symlink case, and two non-discriminating gap fixtures.
3. **One real guard fail-open is fixed:** `{"protected":[]}` allowed writes to all eleven roots while
   `readConfig()`'s own error message said *"non-empty"*.
4. **`QAX-SEC-02` is remediated and applied** by migration 136 under owner decision `D3`; **`QAX-SEC-08`**
   by 132/133 under `D1(i)–(iii)`; **`QAX-SEC-01` and `QAX-SEC-03` have no authored fix.** Measured by
   numeric version comparison — **not** by glob, because `1[3-8][0-9]` matches 131.
5. **Three owner-decision homes already exist and three of four are unprotected** (findings §9, §13).
6. **No protected file, finding status, decision state, or manifest was changed.**

## 4 · Commands and expected outcomes

```bash
npm run guard:selftest     # "guard self-test: 60 assertions passed", exit 0
npm run flow:selftest      # PASS line listing 8 assertion groups, exit 0
npm run flow:validate      # valid:true, taskCount:41, blockerStatusDrift:[], authorized:[]
npm run flow               # 0 eligible; derivedStatuses:0 in THIS checkout
npm run check:guards       # prod-refs + migration hygiene + edge config, exit 0
npm run test:contract      # exit 0
node supabase/tests/security/migration-durability-guard.mjs --self-test
node supabase/scripts/check-migration-manifest.mjs
node supabase/scripts/check-function-posture.mjs
```

**Do not run** `supabase/tests/security/run.mjs` or `supabase/tests/ai/run.mjs` — prohibited live
suites, and the shell may hold QA credentials. **The Flutter suite was deliberately not run**: no Dart
file is in the change set, and there is a known disk-exhaustion hazard. Saying why it was skipped is
part of the claim.

## 5 · Protected-asset integrity requirements

All must hold after review:

* `supabase/migrations`, `supabase/expected_applied.json`, `.github/` — **clean**
* All 11 protected roots — **clean**; `docs/adr/`, `MASTER_PRODUCT_DECISIONS.md`, `decision-log.md`,
  `MASTER_REMEDIATION_REGISTRY.md` included
* `permissions.allow` hash **`b5e644572db6`**, identical to `HEAD:.claude/settings.json`
* `permissions.deny` — **absent**
* `OD-QAX-2` and `OD-14` — `proposed`, `owner: null`, `record: null`
* `scripts/protected-paths.json` — 11 roots, `exceptions: []`
* Migration frontier **181**, pending **{182, 183}**, migration 183 blob **`b0b9a30d`**
* No fixtures: the only untracked files are the five intended ones

## 6 · Known limitations and prohibited operations

* **Self-verification, not independent review** — see the header.
* **`Bash` is outside the guard** and cannot be closed locally. Demonstrated three ways, including a
  destination that never appears in the command text (`base64 -d`), which defeats any text matcher.
* **CR-1 … CR-5 open.** CR-1 gates the Bash CI gate's authorization marker, both blocked security
  decisions, and the ledger's ability to verify provenance rather than structure.
* **`state.json` is gitignored**, so queue status is local to this checkout and will not survive a clone.
* **One verification record was overstated** and is corrected in the findings document; the reviewer
  should treat verification notes as claims to check, not as evidence.

## 7 · Added after the first draft — further claims needing reproduction

8. **The hook wiring is now asserted, and the gap it closes was fail-OPEN.** Measured: `node` on a
   missing script exits **1**, and only exit **2** denies — so renaming or moving the guard, or
   deleting the `hooks` block, silently stops all interception. Three mutations (nonexistent path,
   deleted hooks block, real-but-different file) each fail the suite with the specific expected
   assertion. Reproduce by pointing the hook elsewhere **in a copy**.
9. **Fresh-clone reporting.** With `state.json` absent, drift went **24 → 0** and 25 statuses are
   derived from declared blockers. Reproduce by copying `scripts/`, `.skills-agent/tasks.json`,
   `.skills-agent/decisions.json` and `package.json` into an empty directory and running `status`.
   **A trap was measured before implementing and deliberately avoided:** `eligible()` requires status
   `READY`/`RETRY_WAIT`, so storing a derived `BLOCKED_*` would make tasks uneligible *forever*,
   including after their blocker resolved. Only reporting changed; stored state and `eligible()` are
   untouched. Confirm an authorized decision still returns a task to `READY`/eligible.
10. **`QAX-SEC-02 ≡ SEC-PHI-9` and `OD-QAX-9` was answered as `D1(i)-(iii)`.** These reclassify two
    P0 findings from "blocked" to "applied, pending registration". They rest on reading migration
    headers (136; 132/133) against `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:186` and
    `V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md`. **Worth independent reproduction — they are the
    most consequential claims in the change set.**
11. **Two of my own measurement errors were found and corrected**, and a reviewer should assume more
    exist: a glob `1[3-8][0-9]` that matches **131** (briefly made `QAX-SEC-01` look remediated), and
    a `§9` claim that no `OD-*` id carries a status — **`OD-38` does**, in four documents
    (findings §14). A third was a verification note recording "confirmed" on a case-sensitive grep
    that returned 0.

## 8 · Governance-authority phase — claims requiring independent reproduction

12. **The approval procedure has been exercised end to end.** Commit `08e27f7` touched exactly the
    four files `MASTER_PRODUCT_DECISIONS.md` §2's steps name. Reproduce with `git show --stat 08e27f7`.
    This reframes the gap from *"no process exists"* to *"no written rule says who may trigger it"*,
    and that reframing drives the whole proposal — **it deserves checking.**
13. **All four §2 files are protected roots**, so an agent cannot execute the documented procedure
    through the tool layer. Reproduce by feeding each path to the guard and checking for exit 2.
14. **The approver is named but never defined.** 26 `PD-A*` rows; 22 name `Julia`, 4 `engineering`;
    the role label *"product owner"* is used 4× and defined nowhere. Reproduce by parsing the
    8-column table's second-to-last cell — **not** with a loose `grep`, which over-counts (see §9 of
    the authority proposal, where my own 38 was corrected to 22).
15. **`OD-14` is absent from the registry's `Owner?` column** (0 occurrences) while blocking queued
    work — the basis for recommending a 12-identifier initial scope against the owner's stated 11.
16. **The `OD-QAX-9` link is substantively present but formally absent.** `ADR-W1-001` records
    `D1(i)–(iii)` verbatim yet contains **0** occurrences of `OD-QAX-9`; `V5_DECISION_RESOLUTION
    _2026-09-27.md:78` still says `OPEN`. Both dated 2026-09-27. **The "written before the rulings
    arrived" explanation is a hypothesis, not evidence** — a reviewer should test it.
17. **Four of my own measurement errors have been found and corrected** across these phases. Treat
    every figure in every document as a claim to re-measure, not as evidence.
