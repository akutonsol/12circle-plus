# QA write packet — one call to `rebuild_exercise_intelligence()` — HELD

> **HELD. This packet does not authorize the write.** It describes one QA data write: a single call to
> `public.rebuild_exercise_intelligence()` by a named, signed-in content-editor account on the QA project
> `eyqtldjqpgpljlqvpowh`. It may be executed only after the sign-offs in §1 are complete and the
> prerequisites in §5 are resolved.
>
> **Preparation.** Written 2026-10-28 on `feat/engine-gate-approval-contract` at `0ca51d2`, from the
> repository alone. **No QA or production access, RPC call, data write, deployment or function invocation
> occurred while preparing it.**
>
> **Owner direction (chat, 2026-10-28 — intent, not yet recorded through `MASTER_PRODUCT_DECISIONS.md` §2):**
> *"accept `rebuild_exercise_intelligence()` output as satisfying C-1's narrow threshold only if it creates
> at least one `exercise_intelligence` row. This does not approve the generated attributes, certify any
> exercise, or authorize Stage 1."*

**Labels:** **[REPO]** verified in the repository at `0ca51d2` · **[OBSERVED 2026-10-28]** a read-only
QA observation, dated, which **must be recounted immediately before execution** · **[UNVERIFIED]** must
be confirmed by the operator; a mismatch is a STOP.

---

## 1 · Sign-offs — NONE GRANTED

| ID | Item | Value |
|---|---|---|
| **W-AUTH** | Owner authorization for this one QA write. Acceptable evidence: the commit SHA and `file:line` of a decision-log row quoting the owner (as in the Stage 1 packet §1.2). | ______ (unsigned) |
| **W-OP** | Named operator: a person signed in to QA with a **content-editor** account (`user_profiles.role` = `admin` or `content_manager`). Not invented here. | name ______ · account (no password) ______ |
| **W-PRQ1** | Resolution of prerequisite PRQ-1 (§5.1): the four AI-suite checks that assume an empty substrate. Evidence: the commit SHA of the harness change and a green CI `Live AI suite` run ID on the current (empty) substrate. | ______ |
| Window (UTC) | start / end | ______ / ______ |
| Evidence location | outside the repository | ______ |

This packet does **not** authorize human review, Stage 1, Stage 2, any deployment, or the feature flag (§2).

---

## 2 · What this write is — and is not

| Step | Status in this packet |
|---|---|
| **One call to `rebuild_exercise_intelligence()`** | the **only** thing this packet covers |
| Satisfying C-1's threshold | **only** if the write creates **≥ 1** row, per the owner direction above — and only once that direction is recorded |
| Approval of any generated attribute | **no.** Rows are `draft`, confidence 40, heuristic. This is **not human approval and not clinical validation.** |
| Certifying any exercise for Program Builder | **no.** Certification needs content approval, instructions and alternatives (182); approval needs 187's fingerprinted human review (§9) |
| Human intelligence review | **separate and later.** It belongs after migration 187, or it is demoted |
| Stage 1 (182–186) | **separate:** its own packet, recordings and sign-offs |
| Stage 2 (187–195) | separate |
| Deploying `enrich-exercise-*` / AI enrichment | separate. Not deployed on QA **[OBSERVED 2026-10-28]**; open P1 `QAX-SEC-07` |
| `rebuild_movement_graph()` (the **other** "Rebuild" in the Content Center) | **not authorized.** It is a different write. |
| `ENGINE_WEEK_GENERATION` | stays **off** |

---

## 3 · The RPC — repository-verified

| Property | Value | Source |
|---|---|---|
| Name and signature | `public.rebuild_exercise_intelligence()` — no arguments | [REPO] `087:54` |
| Returns | `jsonb` — `{"profiles": <n>}` | `087:87` |
| Language / security | `plpgsql`, `SECURITY DEFINER` | `087:55` |
| `search_path` | Not set in 087. It is pinned to `public, pg_temp` by the definer-function loops in 116, 118 and 122; CI's live FG-1 posture check passed in run `40625956935`. | [REPO] `116:77`, `118:284`, `122:71` |
| EXECUTE | granted to `authenticated` | [REPO] `087:90`; 116's allowlist (`116:467`) |
| Authorization | `if not public.is_content_editor() then raise exception 'forbidden'`. `is_content_editor()` = the caller's `user_profiles.role` in (`admin`, `content_manager`) | [REPO] `087:58`, `083` |
| Service-role call | has no `auth.uid()`, so it is **refused** (`forbidden`). The write must be made by a signed-in content editor. | [REPO], inferred from the two lines above |
| Rows it visits | **every** `custom_exercises` row | [REPO] `087:59` |
| What it inserts, per exercise | `goal_strength/hypertrophy/power/endurance/fat_loss`, `local_fatigue`, `systemic_fatigue`, `recovery_cost`, `technical_complexity` from fixed heuristics (goal tags; compound or not), with **`source 'derived'`, `status 'draft'`, `confidence 40`** | [REPO] `087:62-77` |
| On an existing row | updates the heuristic columns and `updated_at` **only `where ei.status = 'draft'`**. It never changes `status`, `source` or `confidence`, and never touches a non-draft row. | [REPO] `087:78-84` |
| Not written | Of 187's eight attribute groups, the insert touches only columns of **3** — `programming_goals` (`goal_*`), `fatigue` (`local_fatigue`, `systemic_fatigue`, `recovery_cost`), `biomechanics` (`technical_complexity`) — and leaves **5** empty: `joint_stress`, `contraindications`, `rep_ranges`, `loading`, `coaching`. **`attribute_confidence` is not written.** | [REPO] `087:62-65`; group map `187:36-50` |
| Return value | `profiles` counts **loop iterations** (`custom_exercises` rows visited), **not rows written** — it is not evidence of how many rows were inserted | [REPO] `087:85-87` |
| Column default | `exercise_intelligence.status` defaults to **`'approved'`** (085). The insert sets `'draft'` explicitly, so the default is not used — §7 verifies this. | [REPO] `085:46-47` |
| Triggers on `exercise_intelligence` | none at or below migration 186 (187 adds some). Not applicable now. | [REPO] |
| Atomicity | one RPC call runs as one statement, so a failure leaves nothing written **[standard PostgreSQL behaviour; UNVERIFIED on QA]** | — |
| App path | `ExerciseContentCenterScreen` (`/content-center`) → `CustomExerciseService.rebuildExerciseIntelligence()` → `rpc('rebuild_exercise_intelligence')` | [REPO] `exercise_content_center_screen.dart:408`, `custom_exercise_service.dart:413-415`, `app_router.dart:255` |

---

## 4 · Target verification — before any read or write

1. The app build used for the write points at QA: its defines come from `apps/mobile/dart_defines/qa.json`,
   whose URL host is `eyqtldjqpgpljlqvpowh.supabase.co` **[REPO]**. **STOP** if the build's backend cannot
   be shown to be that host.
2. For the read-only queries, the connection host is exactly `eyqtldjqpgpljlqvpowh.supabase.co` (or the
   QA pooler for that ref). **STOP** if `nxdbooufqzkpslkcogxc` (production) appears anywhere in the
   connection string, or the target is ambiguous.
3. Read-only enforcement, as in the Stage 1 packet §5:
   `PGOPTIONS='-c default_transaction_read_only=on' psql "$QA_DB_URL" -X -v ON_ERROR_STOP=1 -f <file> -o <out>`,
   after `show default_transaction_read_only` prints `on`. Or a GET-only REST script that never touches
   `/rpc`. **STOP** if read-only cannot be shown.
4. No CI run in flight on **any** branch:
   `gh run list --repo akutonsol/12circle-plus --limit 30 --json status -q '[.[]|select(.status!="completed")]|length'`
   prints `0`. No push, merge or CI run from §5 to §7.

---

## 5 · Preflight

### 5.1 Prerequisite PRQ-1 — CI's AI suite assumes an empty substrate (addressed locally, NOT yet validated)

**Four** passing checks in CI's `Live AI suite` depend on `exercise_intelligence` being empty **[REPO]**.
An earlier version of this packet listed only the first two.

| # | Check | Kind | Why it would flip after this write |
|---|---|---|---|
| 1 | `j02-safety-inputs.mjs` **F-J-06** — was *"the intelligence substrate is unpopulated"* (`profiled === 0`) | characterization | about one profile per exercise after the rebuild |
| 2 | `j03-engine-boundary.mjs` **F-J-08** — *"an empty substrate yields HTTP 200 and an empty workout"* | characterization | the request becomes plannable |
| 3 | `j03-engine-boundary.mjs` J-03B — *"the empty selection carries no rules_triggered"* | **invariant** | populated selections record rejection rules such as `EQUIPMENT_CONSTRAINT` |
| 4 | `j04-provenance-authz.mjs` **F-J-08** — *"recorded decisions triggered no rule and rejected nothing"* (`decision_analytics`) | characterization | later generations (d04/d05 make some on every CI run) record rules; decision traces persist |

Before this work the AI harness could not express a skip: a failed check of either kind counted as a
failure (`supabase/tests/ai/lib.mjs`).

**Local change prepared (uncommitted, unpushed, not yet run against QA):**
- the AI harness gained `skip()` with the security suite's semantics: never a pass or a failure, reported
  separately, and an all-skipped suite reads `SKIP`, not `PASS`;
- #2, #3 and #4 are asserted unchanged on an empty substrate, **skipped** on a populated one, and
  **failed** if the state cannot be established (the probe must confirm a content-editor reader, since
  117 hides the table from everyone else);
- #1 is **retargeted** to the defect it exists to pin — no profile carries `contraindications` or a
  `joint_stress` value ≥ 6, the conditions under which `score_exercise` (087:139-147) penalises an injury.
  A rebuild leaves that true, so #1 keeps passing for the right reason;
- an offline self-test (`supabase/tests/ai/selftest.mjs`) proves a skip is never a pass.

**This test-harness change is a PREREQUISITE, not authorization to perform the rebuild.** PRQ-1 counts as
resolved only when the change is committed, pushed with the owner's authorization, and green in CI's
`Live AI suite` on the **current, empty** substrate. W-PRQ1 records that evidence (commit SHA and CI run
ID). **STOP** if W-PRQ1 is blank, or if that CI run was not green.

### 5.2 Function identity on QA (read-only)

```sql
select pg_get_functiondef('public.rebuild_exercise_intelligence()'::regprocedure) as def;
select p.prosecdef, p.proconfig from pg_proc p where p.oid = 'public.rebuild_exercise_intelligence()'::regprocedure;
```

| Check | Expected | Record |
|---|---|---|
| definition contains `is_content_editor()`, `from custom_exercises`, `'derived', 'draft', 40`, `where ei.status = 'draft'` | all four present | ______ |
| `prosecdef` | `true` | ______ |
| `proconfig` | contains `search_path=public, pg_temp` | ______ |

**STOP** on any mismatch: QA's function is not the one this packet describes.

### 5.3 Before counts (read-only, aggregates only)

Save as `<evidence-dir>/rebuild_counts.sql`; run it before (§5.3) and after (§7):

```sql
select count(*) as intelligence_total from public.exercise_intelligence;
select status, source, count(*) as n from public.exercise_intelligence group by 1, 2 order by 1, 2;
select count(*) as approved_total from public.exercise_intelligence where status = 'approved';
select count(*) as exercises_total from public.custom_exercises;
-- aggregate fingerprint of every NON-draft row: detects any change to them without printing ids
select status, source, count(*) as n,
       md5(string_agg(exercise_id::text || '|' || coalesce(updated_at::text, '') || '|' || coalesce(confidence::text, ''),
                      ',' order by exercise_id)) as fingerprint
  from public.exercise_intelligence where status <> 'draft' group by 1, 2 order by 1, 2;
select count(*) as non_40_confidence_derived_drafts from public.exercise_intelligence
 where source = 'derived' and status = 'draft' and confidence <> 40;
select count(*) as orphans from public.exercise_intelligence e
  left join public.custom_exercises c on c.id = e.exercise_id where c.id is null;
```

| Measure | Last observation | Expected now | Record |
|---|---|---|---|
| `intelligence_total` | **0** **[OBSERVED 2026-10-28]** | **0**. If > 0, C-1's threshold may already be met and this write may be unnecessary: **STOP and ask the owner.** | ______ |
| `exercises_total` | **621** **[OBSERVED 2026-10-28]** | > 0, recorded as N | ______ |
| `approved_total` | 0 | recorded | ______ |
| non-draft fingerprints | — | recorded verbatim | ______ |

### 5.4 Operator role (read-only)

The operator confirms their **own** role, `select role from public.user_profiles where id = auth.uid();`
run as themselves, or by an equivalent read the owner accepts, without printing other users' data. It must
be `admin` or `content_manager`; otherwise the RPC refuses (`forbidden`). **STOP** if it is anything else.

---

## 6 · The write — once

1. Sign in to the QA app build (§4.1) as the W-OP account.
2. Open **Content Center** (`/content-center`). Find the **intelligence** section — the one whose empty
   state reads *"Intelligence layer offline — apply migration 087, then Rebuild."* — and tap **its**
   **Rebuild**. **Not** the graph section's Rebuild above it (`rebuild_movement_graph`, not authorized).
3. Tap once. Do not retry.

| Expected | Record (verbatim) |
|---|---|
| activity log: *"Intelligence profiles derived — N exercises."*, with N = §5.3 `exercises_total` | ______ |

**STOP** on *"✗ Intelligence rebuild failed — apply migration 087 (MIE Phase 2)."* The app shows that same
text for **every** error, including an authorization refusal (`exercise_content_center_screen.dart:409-411`)
**[REPO]**, so it is not evidence that 087 is missing. Record it and stop; do not retry.

*A direct REST call to `/rest/v1/rpc/rebuild_exercise_intelligence` is not described, because it would
mean handling a user access token by hand. Using it needs the owner's separate approval.*

---

## 7 · After — read-back (the same `rebuild_counts.sql`)

| Measure | Expected (if `intelligence_total` was 0 before) | Record |
|---|---|---|
| `intelligence_total` | **= N** (`exercises_total`), and in any case **≥ 1** | ______ |
| by status / source | **only** `draft` / `derived` | ______ |
| `approved_total` | **unchanged** (0) | ______ |
| non-draft fingerprints | **identical** to §5.3 | ______ |
| `non_40_confidence_derived_drafts` | **0** | ______ |
| `orphans` | **0** | ______ |
| `exercises_total` | unchanged (N) | ______ |

**C-1 result:** threshold met **only if** `intelligence_total ≥ 1`, and only once the owner direction is
recorded. The rows are heuristic drafts at confidence 40: **not reviewed, not approved, not clinically
validated, and they certify nothing.**

---

## 8 · Stop conditions (any one ends the window; report, do not repair)

1. The target is production, ambiguous, or not shown to be `eyqtldjqpgpljlqvpowh` (§4).
2. Read-only cannot be shown for the count queries (§4.3).
3. A CI run is in flight on any branch (§4.4).
4. W-AUTH, W-OP or W-PRQ1 is blank, or W-PRQ1's CI run was not green (§1, §5.1).
5. QA's function definition or posture differs from §5.2.
6. `intelligence_total` > 0 before the write (§5.3).
7. The operator's role is not `admin` / `content_manager`, or the RPC reports `forbidden` or any error (§5.4, §6).
8. After the write, any of these:
   - a status other than `draft`, or a source other than `derived`, appears among new rows — in
     particular **any `approved` row** (the column default is `'approved'`);
   - `approved_total` changed;
   - a non-draft fingerprint changed;
   - `intelligence_total` does not equal N when it was 0 before;
   - any confidence other than 40 among derived drafts;
   - any orphan row.
9. The app's log does not match §6, or N differs from `exercises_total`.

---

## 9 · What comes after — each separately authorized

- **Recording.** The owner direction quoted at the top, C-1, C-2 and SEQ-1 are recorded through MPD §2
  (`GOVERNANCE_RECORDING_DRAFT_SEQ1_C1_C2.md`).
- **Stage 1** follows its own packet (`QA_STAGE1_182_186_EXECUTION_PACKET.md`). With ≥ 1 row, §4.5's
  C-1 gate passes; everything else there still applies.
- **Human intelligence review only after migration 187.** Reviews or approvals recorded before 187 are
  demoted at apply and carry no fingerprint. **A row written here cannot be approved as it stands:** 187's
  rule 1 refuses any profile whose `attribute_confidence` map is empty, and this RPC never writes it; five of
  the eight groups are also empty (§3, "Not written"). Enrichment (AI or human) has to come first.
- **Certification** needs content approval, instructions and **alternatives** — 0 of 621 had alternatives
  and 20 had instructions **[OBSERVED 2026-10-28]**.

## 10 · Reversal — not authorized, and not rehearsed

The write is idempotent for drafts: a second call re-derives the same heuristic columns. Removing the rows
would be **another QA write** (for example, deleting `source = 'derived' and status = 'draft'` rows) and
needs its own authorization. If C-1 is then unmet again, Stage 1 is held again.

## 11 · Unresolved before execution

1. **PRQ-1** — the four AI-suite checks that assume an empty substrate (§5.1). A local harness change
   addresses them, but it is uncommitted, unpushed and not yet validated in CI.
2. **W-OP** — no content-editor operator is named; this packet does not invent one.
3. **W-AUTH** — the owner's authorization, recorded per MPD §2.
4. That a single RPC call is atomic on QA (§3) and that QA's function matches the repository (§5.2) —
   both confirmed by the operator on the day.
5. Every count — the 2026-10-28 observations (0 rows, 621 exercises) are recounted at §5.3.
