---
name: cplus-verification
description: Independent verification of a 12circle-plus change — re-deriving the defect, proving the test fails on main and passes on the branch, hunting sibling failure modes, checking negative controls and test reachability, and returning a verdict with evidence. Use when verifying any completed 12circle-plus package (you did not write it).
---

# Independent verification in 12circle-plus

You verify work you did not write. You do not fix the code under test; you report.

## Checklist (all, every time)

1. **Read the diff** against `origin/main` (not the primary checkout). Is the scope exactly the
   package's files? Any protected path touched without the exception procedure?
2. **Re-derive the defect** from the code on main yourself. Does the stated root cause hold?
3. **Failing baseline:** run the new test against main's implementation (revert only the lib files)
   — it must fail *for the stated reason*. A test that passes on main proves nothing.
4. **Passing fix:** run it on the branch.
5. **Reachability:** can the assertion's branch actually be reached? (A refusal test with no
   positive control can pass because the statement is invalid.) Is a count saturated or vacuous?
6. **Siblings:** search for the same defect class elsewhere (same pattern, other screens/tables).
7. **Regression:** full suite count, `flutter analyze` count vs baseline 291, static guards from the
   repo root, relevant replays on both migration shapes.
8. **Cleanup:** stubs removed, no stray files, servers stopped, no secrets in output.

## Verdict

`VERIFIED` (with the evidence lines), `REJECTED` (what fails and why), or `INCONCLUSIVE` (what could
not be run and why). Never round "most checks passed" up to VERIFIED. CI 7/7 on the exact head is
read from GitHub, not assumed.
