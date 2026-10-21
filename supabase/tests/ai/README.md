# Live AI / intelligence decision-integrity suites

QA Workstream J. These run against a **real Supabase project** over the same
REST / RPC / Functions surface a phone uses, with the same anon key and real
JWTs.

A static assertion can tell you that an edge function selects a column. Only a
live call can tell you whether the column exists, whether the function is
deployed, and whether an authorization guard actually composes with PostgREST
and the policies. Both halves are needed, and this is the live one — the static
half is `apps/mobile/test/unit/ai_decision_integrity_test.dart`.

## Running

```bash
export QA_URL=https://<qa-project-ref>.supabase.co
export QA_ANON=<qa anon key>

node supabase/tests/security/setup-identities.mjs   # once — creates the p1-* fixtures
node supabase/tests/ai/run.mjs
```

No service key is required. The suites reuse the four `p1-*@qa.12circle.test`
fixtures that `supabase/tests/security` creates.

## Safety

* The harness **refuses to run against the production project ref** (`lib.mjs`).
* **Read-only by default.** The only checks that write are gated behind
  `AI_ALLOW_WRITES=1` and are listed in
  `docs/QA_WORKSTREAM_J_AI_DECISION_INTEGRITY_REPORT.md` §14.
* The one probe that attempts a profile write (`j02`, F-J-17) restores the prior
  value if it ever succeeds. Today it is rejected, so nothing changes.
* Probes against another coach's program use a week number that is not in any
  plan, so the engine aborts before its `DELETE`.

## Two kinds of assertion

| Kind | Meaning | When it goes red |
|---|---|---|
| `INV` invariant | A property the system must hold. | A regression. |
| `CHAR` characterization | A defect this workstream found, pinned as it behaves today, with its finding ID. | The behaviour changed — either it was remediated (invert the assertion and promote it) or it drifted further. Either way, look. |

Nothing is marked "expected to fail". A red test nobody can act on protects
nothing; a characterization that flips is a signal with an owner.

## Layout

| File | Covers |
|---|---|
| `lib.mjs` | harness: auth, REST/RPC/Functions helpers, column probes, reporting |
| `j01-input-assembly.mjs` | every column each AI feature selects, against the real schema |
| `j02-safety-inputs.mjs` | PAR-Q, allergies, injuries — present, and consumed by nothing |
| `j03-engine-boundary.mjs` | does the deterministic engine run, select, and fail closed |
| `j04-provenance-authz.mjs` | decision_traces content and read scope; engine RPC guards |
| `j05-product-path.mjs` | AI edge-function deployment |
