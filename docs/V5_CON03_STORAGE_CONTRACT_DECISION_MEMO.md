# CON-03 — Canonical Storage Contract for `user_profiles.dietary_restrictions`

## DECISION MEMO · STATUS: **PENDING — NOT REQUESTED, NOT APPROVED**

**This memo was produced as an artifact. No owner was contacted; no authorized route to the
product owner exists in this workflow. The decision has NOT been requested, received, or
approved.** Nothing here may be read as consent.

`MASTER_PRODUCT_DECISIONS.md` is **not modified by this memo.** Its §2 mechanism ("when a
decision is taken… update this document's row to `ANSWERED` with the date and the owner") is
available only to the owner taking the decision. The route used here is the one this programme
already established for surfacing pending decisions — a standalone input package with a
response sheet (`V5_OWNER_INPUT_PACKAGE.md` §H convention).

**Prepared against** `6f2383886f22c9e0f47cd98f45a8e0d12ce4fc1e`, branch
`feat/v5-autonomous-team`, tree clean, local == remote. Production not contacted. No QA write
or live probe. Gate 9B closed.

---

## 1 · The exact decision requested

> **Select the canonical storage representation for `user_profiles.dietary_restrictions`:
> Option A (`text`, comma-joined) or Option B (`text[]`), and answer the six contract
> questions in §5 that the repository cannot answer.**

### 1.1 What is *not* in question

- **PD-A22 does not decide this.** Its `Proceed?` is `**Yes** — via (b)`: authorization to
  design a migration converging from either starting type **without inspecting production**.
  Convergence is about the *starting* state. It does not select the *final* representation.
- **`MASTER_QA_RECONCILIATION.md:316-330` recommends `text[]`.** A recommendation, not a
  decision, and self-qualified: "the choice interacts with prod's actual type".
- **No governing document answers it.** `product-bible.md`, `decision-log.md` and
  `WORKOUT_DOMAIN_CONTRACT.md` contain **no occurrence of "dietary"** at all. So §0.2's
  "already answered by governing documents → a finding, not a decision" path does **not**
  apply here. This is a genuine open decision.
- **`MASTER_PRODUCT_DECISIONS.md` has no row selecting a target type**, and `:6` still states
  "Nothing in this document is decided." Only `PD-A05`, `PD-A23` and §0.1's closed list are
  resolved; `PD-A22` is not among them.
- **Designing is not executing.** Permission to design a migration is not permission to run it.

---

## 2 · The repository is genuinely split — nine artifacts, two intents

This is the central fact. The `text[]` belief is **not** a single stray comment.

### Favouring `text` (current declared contract)

| # | Artifact | Evidence |
|---|---|---|
| 1 | `supabase/migrations/013_health_assessment.sql:15` | `dietary_restrictions TEXT NOT NULL DEFAULT ''` — the declaring migration |
| 2 | `supabase/APPLY_TO_REMOTE.sql:32` | `TEXT NOT NULL DEFAULT ''` — see §2.1 |
| 3 | `supabase/migrations/140_assessment_access.sql:138` | `get_client_assessment()` declares output `dietary_restrictions text` |
| 4 | `supabase/migrations/141_…sleep_hours_type.sql:69` | the **live** function still declares `text` |
| 5 | `apps/mobile/lib/.../intake_data.dart:252` | `toSupabase` → `dietaryRestrictions.join(',')` |
| 6 | `intake_data.dart:170` | read fallback `_splitList(… as String?)` |
| 7 | QA live type | `text` (probe recorded at `MASTER_QA_RECONCILIATION.md:316-330`) |
| 8 | sibling columns | `medical_conditions`, `injury_locations` are `text` + `join(',')` in **both** serializers (`:202`/`:243`, `:204`/`:245`) |

### Favouring `text[]` (an intent held in several places)

| # | Artifact | Evidence |
|---|---|---|
| 1 | `intake_data.dart:213` | `toSupabasePartial` → `dietaryRestrictions.toList()` |
| 2 | `intake_data.dart:168-169` | a first-class `is List` read branch |
| 3 | `supabase/seeds/test_accounts.sql:156` | inserts **`ARRAY[]::text[]`** into the column |
| 4 | `client_detail_screen.dart:773` | comment: "come back as JSON arrays" |
| 5 | `MASTER_QA_RECONCILIATION.md:316-330` | the standing recommendation |

**Correction to Milestone 14.** That report framed the `text[]` belief as one comment copied
from the `activities` pattern. Item 3 above disproves that framing: a committed **seed** also
assumes an array. The intent is systemic, even though it is nowhere recorded as a decision.
The copy-from-`activities` explanation still fits `:213` and the seed's own correct `ARRAY[]`
uses at `:120-121` (coach specialties/certifications, genuine `text[]` columns), but it is no
longer a complete account.

**The seed has never been exercised.** `test_accounts.sql` is referenced nowhere in
`.github/`, `supabase/scripts/`, `scripts/`, `package.json` or `Makefile`. Against a `text`
column `ARRAY[]::text[]` fails outright, so this is a latent error of exactly the kind
`141`'s header describes: it "survived because the suite had never been executed."

### 2.1 `APPLY_TO_REMOTE.sql` — evidence about the out-of-band channel, NOT about production

The registry's CON-03 note reasons that an in-code `text[]` comment "implies an out-of-band
production change." `supabase/APPLY_TO_REMOTE.sql` is that out-of-band channel, committed:
its header reads *"PASTE THIS ENTIRE FILE INTO THE SUPABASE DASHBOARD SQL EDITOR AND RUN IT."*
At `:32` it declares `dietary_restrictions TEXT NOT NULL DEFAULT ''`.

**Labelled as inference, with its limit stated:** this is repository evidence that the manual
channel, as committed, provisions `TEXT`. It is **not** proof of production's current type —
`ADD COLUMN IF NOT EXISTS … TEXT` is a no-op against an existing column of *any* type, so
running this file against a `text[]` column would leave it `text[]`. **Production was not
inspected and this does not substitute for inspecting it.** Q-6 stands unchanged. Milestone 14
did not find this file.

---

## 3 · Option comparison

| | **Option A — `text`** | **Option B — `text[]`** |
|---|---|---|
| **DB representation** | comma-joined scalar; `NOT NULL DEFAULT ''` | array; house style `text[] NOT NULL DEFAULT '{}'` (per `033:20`, `097:17`, `087:36`) |
| **Current repo declaration** | **matches** (`013:15`, `APPLY_TO_REMOTE:32`) | contradicts it |
| **Serializer change** | `:213` `.toList()` → `.join(',')` | `:252` `.join(',')` → `.toList()` |
| **Deserializer change** | none — `:168-170` already handles both | none — same |
| **Migration required** | none for a `text` start; `text[] → text` only if a supported start is `text[]` | `ALTER COLUMN … TYPE text[] USING …` + `SET NOT NULL` + `SET DEFAULT '{}'` |
| **Type-change precedent** | n/a | **none** — zero `ALTER COLUMN … TYPE` in all 182 migrations |
| **SQL function impact** | **none.** `140:138`/`141:69` already declare `text` | **breaks `get_client_assessment()`** — `42804` on every call. Needs DROP + recreate + re-issue of 3 grants (`141:135-137`) |
| **Who breaks** | nothing | `supabase/tests/security/d09-assessment-access.mjs` (live security suite). **No application caller exists** — no Dart/TS call site for the RPC |
| **Seed impact** | `seeds/test_accounts.sql:156` must become `''` | already array-shaped — becomes correct |
| **Sibling consistency** | consistent with `medical_conditions`, `injury_locations` | leaves both siblings on the opposite convention in the same table |
| **Round-trip** | lossless **over the current value domain** — see §4 | lossless unconditionally |
| **Future-proofing** | breaks silently if a comma-bearing value is ever admitted | immune to delimiter concerns |
| **PHI** | `dietary_restrictions` is PHI (`SECURITY_LEDGER_PHI.md:22`) — unchanged either way; no RLS change in either option | same |

---

## 4 · Round-trip: Option A is lossless today, and why that is a *conditional* fact

The brief rightly cautions against claiming `join(',')`/`split(',')` round-trips losslessly if
valid values can contain commas. **Checked directly, not assumed.**

The value domain is a **closed set of nine literals**, hard-coded at
`intake_flow_screen.dart:5734-5737`:

`Vegetarian · Vegan · Gluten Free · Dairy Free · Keto · Paleo · Halal · Kosher · Other`

- **No literal contains a comma.**
- **There is no free-text entry for restrictions.** `'Other'` is itself a chip. The only
  `TextField` on that page writes `foodAllergies` — a *separate* scalar `text` column modelled
  as `String` and never split, which is why its comma-bearing hint ("e.g. Peanuts, shellfish,
  eggs...") is harmless.
- **Exactly one UI writer** (`:505`) and **exactly two column write sites** (`:213`, `:252`).
  `:136` is a DB round-trip; `client_detail_screen:697` and `ai_nutrition` are read-only.
- `_toggle` (`:5749-5754`) removes on re-tap, so **duplicates are unreachable**; **order** is
  selection order and is preserved by `join`/`split`.
- `_splitList` does **not** trim, which is safe only because no literal has leading or
  trailing whitespace.

**So Option A round-trips losslessly today — as a property of the closed set, not of the
encoding.** It holds only while the domain stays closed and comma-free. The unusable `'Other'`
chip actively invites a future free-text field, which would break the encoding silently. If
Option A is selected, the contract must therefore **pin the domain**, not merely change the
serializer (§6.1).

### 4.1 A second, independent product gap this exposed

The app contains **two divergent restriction vocabularies**: intake's nine chips above, and the
meal-plan screen's six (`Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut-Free, Halal`) recorded
at `QA_WORKSTREAM_E_NUTRITION_CHECKIN_RECONCILIATION.md:845-846`. They differ in spelling
(`Gluten Free` vs `Gluten-Free`) and in membership (`Keto/Paleo/Kosher/Other` vs `Nut-Free`).
**Which vocabulary is canonical is a product question that repository evidence cannot settle**,
and it is independent of the type decision. Workstream E's planned fix (`:868`) loads this
column into the meal-plan screen as locked context, so the vocabularies will collide there.

---

## 5 · The six contract questions — which are answered, which need the owner

| # | Question | Status |
|---|---|---|
| 1 | **Canonical DB type** — `text` or `text[]` | **OWNER DECISION REQUIRED.** Unanswered by every authority. |
| 2 | **App boundary representation + serializer behaviour** | **Answered conditionally on #1.** Boundary is `List<String>` either way (`intake_data.dart:43`); both serializers must emit one representation. Read path already converges (`:168-170`) and needs no change. |
| 3 | **null / empty / whitespace / duplicates / ordering** | **Partly answered by code, must be ratified.** Today: `NOT NULL DEFAULT ''` (`013:15`); `''`→`[]` and `[]`→`''`; no trim; duplicates unreachable via `_toggle`; order = selection order. Under B the equivalents are `'{}'`/`{}`. **Owner must ratify** that order is not semantic and duplicates are invalid. |
| 4 | **Are commas allowed inside a value, and if so how are values encoded?** | **OWNER DECISION REQUIRED.** No value contains one today (§4) and nothing *enforces* that. Under A this must become a stated constraint; under B it is moot. |
| 5 | **Compatibility contract for SQL functions, RPCs, consumers** | **Answered as fact, consequence depends on #1.** `140:138`/`141:69` declare `text`; A preserves them, B requires DROP + recreate + 3 grants. Consumers: `auth_provider.dart:96`, `intake_flow_screen.dart:98`, `client_detail_screen.dart:697` (display), `ai_nutrition` (consume), `d09` suite. No RPC call site in app code. |
| 6 | **Backward-compatibility / rollout** | **OWNER DECISION REQUIRED.** Whether the forward migration must still ship when A is chosen and QA is already `text` (the convergence requirement at `MASTER_REMEDIATION_WAVES.md:335` says it must converge from *either* start), and whether production rollout waits on PD-A22 route (a). |

**Three of six require the owner: #1, #4, #6.** Plus the §4.1 vocabulary question.

---

## 6 · Recommendation

**Option A (`text`)** — on cost and consistency, with the reservation in §6.1 stated plainly.

Reasons, each source-backed:

1. It matches the declared contract in **both** provisioning paths (`013:15`,
   `APPLY_TO_REMOTE:32`) and the live QA type.
2. It requires **no DDL**. Option B would be the **first** `ALTER COLUMN … TYPE` in 182
   migrations — no in-repo precedent for the conversion, its locking, or its rollback.
3. It leaves `get_client_assessment()` untouched. Option B reintroduces exactly the `42804`
   defect `141` was written to repair, and `141`'s own header records that a return type
   "cannot be changed by `CREATE OR REPLACE`" — so DROP, recreate, and re-issue `141:135-137`.
4. It keeps the three intake list-columns on one convention. Option B leaves two of three on
   the opposite convention in the same table, read by the same screen.
5. Total change under A: **one serializer line, one seed line, two stale comments.**

**I am not treating this as settled.** §2 shows a real `text[]` intent in four places including
a committed seed, and Option B is strictly more robust on §4 and §5 semantics. If the product
intends restrictions to become open-ended — which the dead `'Other'` chip hints at — **Option B
is the better long-run choice and the recommendation should be re-weighed.** That is a product
judgement, not an engineering one.

### 6.1 If Option A is selected, the encoding must be constrained, not assumed

A serializer change alone leaves the losslessness in §4 resting on an unenforced property.
Option A must additionally include **one** of:

- (i) a `CHECK` constraint rejecting values outside the canonical vocabulary, or
- (ii) a `CHECK (position(',' in dietary_restrictions) = 0)`-style guard on individual
  elements plus a documented vocabulary, or
- (iii) a documented contract + a Dart-side guard test asserting no canonical value contains
  the delimiter.

(iii) is the minimum and the only one needing no DDL; (i) is strongest but is a schema change
requiring its own authorization. **Which, is part of decision #4.**

---

## 7 · Implementation plan — both options, neither executed

Common to both: **one** final canonical representation; the forward migration must converge
from **either** supported starting type (`MASTER_REMEDIATION_WAVES.md:335`); migrations are
**forward-only** (`141`: "140 is NOT rewritten in place"); **no sibling column is touched** —
no authority places `medical_conditions`/`injury_locations` in CON-03's scope, and §1.1 of the
Milestone 14 design shows both are already self-consistent.

### 7.1 Option A — files that would change

| File | Change | Why |
|---|---|---|
| `apps/mobile/lib/.../intake_data.dart:211-214` | `.toList()` → `.join(',')`; delete the false comment | the defect itself |
| `supabase/seeds/test_accounts.sql:156` | `ARRAY[]::text[]` → `''` | otherwise the seed cannot run against the canonical type |
| `apps/mobile/lib/.../client_detail_screen.dart:773` | correct the "JSON arrays" comment | it documents the wrong contract; `_str` stays as-is (defensive, still correct) |
| new migration `18x_…` | **only if** a supported start may be `text[]`: `ALTER … TYPE text USING COALESCE(array_to_string(col, ','), '')` guarded by a type probe on `information_schema.columns` | convergence requirement |
| guard test | assert no canonical vocabulary value contains `,` and both serializers agree | §6.1(iii) |

**Open sub-question for the owner (#6):** whether the convergence requirement obliges shipping
the `text[] → text` migration at all when QA is already `text`. A type-probing, idempotent
migration satisfies it without asserting prod's type.

### 7.2 Option B — files that would change

| File | Change | Why |
|---|---|---|
| new migration `18x_…` | `ALTER COLUMN … TYPE text[] USING CASE WHEN col IS NULL OR col = '' THEN '{}'::text[] ELSE string_to_array(col, ',') END`, then `SET NOT NULL`, `SET DEFAULT '{}'`; idempotent under a `text[]` start | the conversion. The `col = ''` guard is load-bearing because `DEFAULT ''` makes empty string the common value, and it is written so that `string_to_array('', ',')`'s exact result cannot matter |
| same migration | `DROP FUNCTION public.get_client_assessment(uuid)`; recreate with `dietary_restrictions text[]`; re-issue `141:135-137` | `141`'s stated precedent; otherwise `42804` on every call |
| `intake_data.dart:252` | `.join(',')` → `.toList()` | one serializer |
| `client_detail_screen.dart:773` | comment becomes correct as written | — |
| `supabase/tests/security/d09-assessment-access.mjs` | re-verify against the new signature | it is the only exerciser |
| seed | already correct | — |

**Not resolvable offline:** whether `array_to_string`/`string_to_array` behave as specified
here cannot be executed on this runner (§9 of the Milestone 14 design: libpq client-only, no
`postgres` server, docker down). Either option's migration needs a real server or authorized
QA execution before it may be called verified.

---

## 8 · Response sheet

```
CON-03-TYPE     : Option __    (A = text, comma-joined · B = text[])

CON-03-COMMA    : may a dietary-restriction value contain a comma?   Y / N
                  if Y and Option A: encoding ______________________
                  if N: enforce by  (i) CHECK constraint  (ii) element guard  (iii) doc + test

CON-03-ROLLOUT  : must the forward migration ship even when QA already matches
                  the chosen type?                                   Y / N
                  production rollout waits on PD-A22 route (a)?       Y / N

CON-03-VOCAB    : canonical restriction vocabulary —
                  intake's 9 chips / meal-plan's 6 / a new list ______________
                  (independent of the type decision; see §4.1)

CON-03-SEMANTICS: ratify — order is NOT semantic, duplicates are invalid,
                  empty means "none declared"                         Y / N
```

---

## 9 · Boundary

No migration file created. No product-code change. `MASTER_PRODUCT_DECISIONS.md`,
`MASTER_REMEDIATION_REGISTRY.md` and `QA_CLOSURE_STANDARD.md` not modified. No QA write, live
probe, schema, RLS or policy change. Production `nxdbooufqzkpslkcogxc` not contacted. No
credential or secret accessed. No SEC-R2/SEC-R3 promotion or evidence-count change. No C1
widening. The §7.10 / §7.18 Step 4 authority conflict untouched. **The decision is PENDING and
was never requested of any owner.**
