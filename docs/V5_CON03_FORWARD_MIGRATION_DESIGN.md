# CON-03 — Forward-Migration Design (PROPOSAL, NOT EXECUTABLE)

**Status:** DESIGN PROPOSAL. **Blocked on one owner decision** (§2).
**Authorization:** PD-A22 `Proceed? = "Yes — via (b)"` — design a migration that converges
from either starting type **without inspecting production**. That is the whole of what is
authorized. It is not authorization to execute anything, anywhere.
**Nothing in this document has been applied to any database.** No QA write, no live probe,
no migration execution. Deliberately **not** placed under `supabase/migrations/` so that no
runner, CLI, or reviewer can mistake it for an applicable migration.

---

## 1. The defect, restated from source

`user_profiles.dietary_restrictions` is written by two serializers that disagree:

| site | code | sends |
|---|---|---|
| `intake_data.dart:213` (`toSupabasePartial`, per-step save) | `dietaryRestrictions.toList()` | JSON **array** |
| `intake_data.dart:252` (`toSupabase`, final save) | `dietaryRestrictions.join(',')` | **String** |

QA's column is `text` (probe recorded in `MASTER_QA_RECONCILIATION.md:316-330`:
`operator does not exist: text && unknown`, while control column `activities` accepted the
array operator). An array sent into a `text` column fails; `_saveProgress`'s
`catch (_) {}` (`intake_flow_screen.dart:168-174`) then discards **the entire step's intake
data** silently. That is CON-03.

### 1.1 Scope is ONE column, not three — correcting the 140 note

`140_assessment_access.sql:209-216` notes that `medical_conditions`, `injury_locations` and
`dietary_restrictions` are all modelled `List<String>` over `TEXT`. True about the modelling.
But only one has the **serializer disagreement**:

| column | `toSupabasePartial` | `toSupabase` | consistent? |
|---|---|---|---|
| `medical_conditions` | `join(',')` `:202` | `join(',')` `:243` | yes |
| `injury_locations` | `join(',')` `:204` | `join(',')` `:245` | yes |
| `dietary_restrictions` | `toList()` `:213` | `join(',')` `:252` | **NO** |

The siblings comma-join uniformly and round-trip correctly through `_splitList`. **CON-03 is
a one-column defect.** Any remediation that changes all three is wider than the finding.

### 1.2 Probable origin

`:184` sends `activities.toList()`, and `activities` is the column the QA probe confirmed
*is* `text[]`. The comment at `:212` — "Live column is text[] — send a real array" — is
true of `activities` and false of `dietary_restrictions`. The pattern appears to have been
copied along with its justification.

---

## 2. THE BLOCKER — the target representation is undecided

PD-A22 authorizes **route (b)** (converge from either starting type). It does **not** name a
target. Searching the authority documents:

- `MASTER_QA_RECONCILIATION.md:316-330` — "**Recommend** migrating the column to `text[]`".
  A recommendation, explicitly qualified: "the choice interacts with prod's actual type".
- `MASTER_PRODUCT_DECISIONS.md` — contains **no decision naming a target type**, and `:6`
  states "Nothing in this document is decided." §0.1's closed list names only PD-A20.
- `140:209-216` — "The return types above follow the DATABASE, which is authoritative",
  while in the same note calling TEXT a shape that "round-trips badly".

So the two in-repo signals point opposite ways and neither is a decision. **Per the brief I
have not invented one.** §3 is valid under either target; §4 prices each.

**Decision required of the owner:** target representation for
`user_profiles.dietary_restrictions` — `text` or `text[]`.

---

## 3. What is settled regardless of the target

### 3.1 The delimiter is NOT ambiguous — code answers it

I expected the delimiter to be an open question. It is not. The read path already converges
from both types, `intake_data.dart:168-170`:

```dart
dietaryRestrictions: d['dietary_restrictions'] is List
    ? List<String>.from((d['dietary_restrictions'] as List).map((e) => '$e'))
    : _splitList(d['dietary_restrictions'] as String?),
```

and `_splitList` (`:123-126`) is exactly:

```dart
if (raw == null || raw.isEmpty) return [];
return raw.split(',');
```

Comma, **no trim, no empty-filtering**. Any `text → text[]` conversion must reproduce these
semantics or it changes what existing rows mean.

**Consequence: the client read path needs no change under either target.** It already
handles both. Only the write side must be made to agree.

### 3.2 The conversion expression, and why it is written defensively

```sql
-- text -> text[]
CASE WHEN col IS NULL OR col = '' THEN '{}'::text[]
     ELSE string_to_array(col, ',') END

-- text[] -> text          (inverse of _splitList)
COALESCE(array_to_string(col, ','), '')
```

The `col = ''` guard is load-bearing. `013_health_assessment.sql:15` declares the column
`TEXT NOT NULL DEFAULT ''`, so **empty string is the overwhelmingly common stored value**.
`_splitList` maps `''` → `[]`, so the conversion must map `''` → `{}`.

I could not execute `string_to_array('', ',')` to confirm whether it yields `{}` or `{''}`
(§5). The guard is written so that **the answer does not matter** — the `''` case never
reaches `string_to_array`. That is deliberate: an unverifiable detail should not be load-bearing.

### 3.3 Known lossiness, stated plainly

`text → text[]` is lossy for any value **containing a comma**: `'no nuts, no shellfish'`
becomes two elements. This is not introduced by the migration — `toSupabase:252` already
comma-joins, and `_splitList` already splits, so such a value is *already* corrupted on
round-trip today. The migration preserves the existing (lossy) convention rather than
inventing a new one. Fixing comma-containing values is a separate concern from CON-03.

### 3.4 No precedent for a column type change

**Zero** `ALTER COLUMN … TYPE` statements exist across all 182 committed migrations
(verified by grep with a positive control). A CON-03 type conversion would be the **first in
the project's history**. `text[]` columns *are* conventional, though —
`033_womens_health.sql:20` `symptoms text[] NOT NULL DEFAULT '{}'`, `097:17`, `087:36,40` —
so the house style for an array column is `text[] NOT NULL DEFAULT '{}'`.

---

## 4. The two targets, priced

### 4.1 Target = `text` (no schema change)

Change `:213` from `.toList()` to `.join(',')`, delete the incorrect comment.

- Schema change: **none**. Data conversion: **none**. Migration: **none**.
- Matches `013:15`, matches both sibling columns, matches `140`'s "the database is authoritative".
- Converges from either starting type only if prod is already `text`; if prod is `text[]`, a
  `text[] → text` migration (§3.2 inverse) is needed there.
- Risk: lowest. One-line client change, no first-of-its-kind DDL.

### 4.2 Target = `text[]` (the registry's recommendation)

Requires **three** coordinated changes, not one:

1. `ALTER TABLE user_profiles ALTER COLUMN dietary_restrictions TYPE text[] USING <§3.2>`,
   plus `SET NOT NULL`, `SET DEFAULT '{}'`.
2. Change `:252` to `.toList()`.
3. **A third drop/recreate of `get_client_assessment()`.** `141:69` (the live version)
   declares the output column `dietary_restrictions text`. 141's own header records that a
   `RETURNS TABLE` signature is validated at **execution** time, so a mismatch yields
   `42804 — structure of query does not match function result type` on **every call**, and
   that a return type "cannot be changed by `CREATE OR REPLACE`" — the function must be
   dropped, recreated, and its grants re-issued.

   **Choosing `text[]` therefore reintroduces exactly the defect 141 was written to repair.**
   This is a precedented, documented consequence, not a prediction.

4. Leaves `medical_conditions` / `injury_locations` on the opposite convention from their
   sibling, in the same table, read by the same screen.

### 4.3 My recommendation, with the reason

**Target = `text` (§4.1).** The evidence found in this milestone inverts the registry's
recommendation: `text[]` is the more expensive option (first-ever type conversion + data
migration + a third function drop/recreate that re-opens a closed defect class), and it
*reduces* consistency inside `user_profiles`, because the two sibling columns stay `text`.
`text` achieves CON-03's stated "one serializer, one type" with a one-line change and no DDL.

This is a recommendation. **The decision is the owner's** and I have not acted on it.

---

## 5. Offline verification — ATTEMPTED, NOT POSSIBLE, and a correction

I attempted real behavioural verification in an isolated ephemeral cluster and **it could not
be built on this runner.**

- `initdb` and `pg_ctl` resolve to `/opt/homebrew/opt/libpq/bin/` — the **client** keg.
  `initdb` fails: `program "postgres" is needed by initdb but was not found`.
- No `postgresql@*` keg, no `postgres` binary anywhere under `/opt/homebrew/Cellar`, none on PATH.
- Docker daemon not running.

**Correction to my own prior report.** I previously reported that a safe ephemeral harness
"does exist" and its binaries were "functional", on the strength of `initdb --version` and
`pg_ctl --version` both returning `18.6`. Those succeed in libpq's wrappers while the server
they drive is absent. A version flag is not a capability check.

**Secondary finding — `negative-control.sh` cannot detect this either.** Its `find_pg` guard
(`:98-100`) tests `-x "$PGCTL" && -x "$INITDB" && -n "$PSQL"`. All three pass here, so the
guard admits the runner and the script then dies inside `initdb`. The message it would have
printed ("PostgreSQL server binaries … are not available on this runner") describes the real
condition correctly; the check simply cannot reach it. A `postgres` presence test would fix it.

**A second, independent reason — and it is a safety mechanism working correctly.**
`negative-control.sh`'s `assert_no_credentials` (`:76-90`) does **not** unset credential
variables; it **refuses to run** if any of nine is set, on the stated grounds that "a set
variable means the job scope has widened and the harness refuses rather than proceeding."
`QA_URL`, `QA_SERVICE` and `QA_ANON` *are* set in this shell, so the harness would `die2`
before reaching any database work. **I did not work around this and must not.** (This also
corrects my own earlier description of the guard as "guards/unsets": fail-closed refusal is
strictly stronger than sanitising, and the stronger behaviour is what is implemented.)

**Isolation was verified before anything ran** (per the brief): in my own attempt, every
QA/Supabase/DB environment variable was cleared in the subshell, host pinned `127.0.0.1`,
port 55433, data directory inside the session scratchpad, which was then deleted. Nothing
reached QA or production — the cluster never started at all.

**Verification position:** §3.2's conversion semantics are **unverified behaviourally** and
derived from `_splitList`'s source plus PostgreSQL semantics. §3.1, §1.1, §3.4 and §4.2(3)
are verified from repository source. Behavioural verification of the conversion requires
either a `postgresql` server on the runner or authorized QA execution — neither is in scope here.

---

## 6. Wave / dependency status

- CON-03 gates **Wave 3B-1**, which with SEC-R2 gates **SEC-R3**'s failure-path leg
  (`V5_SECR3_FAILURE_PATH_READINESS.md`). CON-03 remaining undecided keeps 3B-1 unstartable.
- 3B order is strict: 3B-0 → 3B-1 → 3B-2 → 3B-3 → 3B-4 → 3B-5 (only 3B-2 ∥ 3B-4).
- Q-6 (`MASTER_QA_RECONCILIATION.md:513`) stands: production is not inspected and will not be
  without explicit authorization. Confirming prod's type is "a prerequisite to a production
  rollout, not to QA work" — consistent with PD-A22's "(b) now, (a) before rollout".

## 7. Execution boundary — what I did not do

No migration file created. No QA write, live probe, or schema change. Production
`nxdbooufqzkpslkcogxc` not contacted. No target invented. No registry or closure-standard row
mutated. Creating a migration file would not be permission to execute it, so none was created.
