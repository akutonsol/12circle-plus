# Governance recording draft — SEQ-1, C-1, C-2, OA-2 — DRAFT, NOT RECORDED

> **This is proposed text only. None of these decisions is formally recorded.**
>
> Under `V5_OWNER_AUTHORITY_DIRECTION_2026-10-21.md` §1, a direction given in conversation expresses
> intent, not authorization. A decision takes effect only once it is recorded through
> `MASTER_PRODUCT_DECISIONS.md` §2 with owner attribution, scope, status and auditable repository evidence.
>
> This file does that preparation work only. It edits no governance file. Every file it proposes to
> change (`docs/decision-log.md`, `docs/MASTER_PRODUCT_DECISIONS.md`,
> `docs/MASTER_REMEDIATION_REGISTRY.md`, `docs/REMEDIATION_PROGRESS.md`,
> `supabase/expected_applied.json`) is a **protected path**. Each edit needs the owner's authorization
> and the temporary `scripts/protected-paths.json` exception, reverted immediately.
>
> Prepared 2026-10-28 on `feat/engine-gate-approval-contract` at `b74a8fc` and revised the same day with the
> owner's further directions (§0). No QA or production access.

## 0 · The three directions being recorded

| ID | Direction (owner, in chat) | Date given | Recorded? |
|---|---|---|---|
| **SEQ-1** | Option 1: Stage 1 (182–186) is applied **before** PR #14 merges | 2026-10-27 | **No** |
| **C-1** | Hold migration **183** while the existing recorded condition is unsatisfied: QA's exercise substrate must be non-empty. Do not override the condition; do not apply 183. Further: *"Keep Stage 1 held while `exercise_intelligence` has zero rows. Do not bypass the existing condition or propose a migration workaround."* | 2026-10-28 | **No** |
| **C-2** | The intended Stage 1 scope is **182–186**, and this scope change must be formally recorded before execution. Formal recording materials: §1 (rows 3–4), §2, §3. | 2026-10-28 | **No** |
| **Substrate definition** | *"Use a count greater than zero in `exercise_intelligence` as the current threshold, while explicitly stating that this does not establish exercise eligibility or approval."* | 2026-10-28 | **No** |
| **OA-2** | Prepare an owner-worded approval draft for review; not signed or recorded. Draft: §5. | 2026-10-28 | **No** |

### 0.1 The consequence of C-1 — accepted by owner direction (2026-10-28), not yet recorded

C-1, as directed, gates **all of Stage 1**, not only 183. The repository evidence:

- `supabase db push` applies every unapplied version, in order, from the migration directory it runs in. CLI
  2.107.0 has no option to apply up to a given version (`QA_BATCH_182_184_185_RUNBOOK.md` §2).
- The only checkout that cannot reach 187+ is `main`, which holds 182, 183, 184, 185 and 186 together.
  A push from it applies 183 with the rest.
- 186 must follow 183, because 186 replaces 183's body (manifest 183 gate, item 3).
- `--include-all` is forbidden: applying 183 *after* 186 would reinstate the broken engine (runbook §2).

**Therefore, while QA's substrate is empty, none of 182, 184, 185 or 186 can be applied by the approved
method.** That includes the P0 fix (184, `QAX-SEC-01`) and the P1 fix (185, `QAX-SEC-03`). No workaround
is proposed here. Anything else — a different migration order, a split of 183, or a renumbering — would
be a new decision for the owner. **The owner's 2026-10-28 direction keeps Stage 1 held on this basis and
excludes any migration workaround.**

Two further facts for the owner:
- the substrate was last observed **empty** (0 `exercise_intelligence` rows, 2026-10-25, read-only);
- making it non-empty on QA means running the content pipeline (enrichment), which is itself a QA write
  needing separate authorization.

### 0.2 The substrate threshold — owner direction 2026-10-28, not yet recorded

- **Current threshold:** `select count(*) from public.exercise_intelligence` **> 0**. This is the measure
  every prior document used for "substrate" (runbook §3 of the 182→186 version; packet §4.5). The
  2026-10-25 decision-log row said *"QA's exercise substrate"* without defining it.
- **What the threshold does NOT establish:** that any exercise is **eligible** or **approved**. A row
  counts whatever its status (draft, under review, needs revision, approved). Eligibility for Program
  Builder needs more, and later: 182's certification for `program_generator`, 187's fingerprinted review of
  all eight attribute groups, and 188's gate. **Satisfying the threshold satisfies only C-1's condition on
  183.**

---

## 1 · Proposed `docs/decision-log.md` rows

Section **"Notable engineering calls (with trade-offs)"**, table `| Date | Decision | Why |`.
`<RECORDING DATE>` is filled in when recorded, not before.

**Row 1 — SEQ-1**

> | `<RECORDING DATE>` | **QA migration sequencing (SEQ-1): Stage 1 (182–186) is applied before PR #14 merges.** (Product owner, in chat, 2026-10-27: *"SEQ-1 Option 1 is approved — Stage 1 (migrations 182–186) must precede merging PR #14."*) Stage 1 runs from a checkout of `main` holding only 000–186; PR #14 (187–195) is not merged until Stage 1 is applied, declared and verified live. | A push applies every unapplied migration in the directory it runs from, and 187 (approval demotion) is one-way. A `main` checkout cannot contain 187, so the irreversible step cannot be reached by accident. Trade-off: PR #14's manifest must be updated after Stage 1 is declared (a conflict, an extra CI cycle). Options considered: `QA_BATCH_182_184_185_RUNBOOK.md` §3. |

**Row 2 — C-1**

> | `<RECORDING DATE>` | **Migration 183 stays conditional on a non-empty QA exercise substrate (C-1), reaffirming the 2026-10-25 condition.** (Product owner, in chat, 2026-10-28: *"Hold migration 183 while the existing recorded condition remains unsatisfied: QA's exercise substrate must be non-empty. Do not override this condition or apply migration 183."*) The *route A* direction recorded only in the manifest's 183 gate text ("183 ships unchanged") is **not** adopted where it conflicts with this condition. Threshold (owner, 2026-10-28): `count(*)` of `exercise_intelligence` **> 0** — this does **not** establish that any exercise is eligible or approved. | The 2026-10-25 row conditioned 183 on the substrate *"since otherwise every programme generation on QA would start (correctly) failing."* Consequence, accepted by the owner (2026-10-28: *"Keep Stage 1 held while `exercise_intelligence` has zero rows. Do not bypass the existing condition or propose a migration workaround."*): one `db push` from `main` cannot skip 183, so **while the substrate is empty no part of Stage 1 (182, 184 P0, 185 P1, 186) can be applied by the approved method**; populating the substrate is a separately authorized QA content task. |

**Row 3 — C-2**

> | `<RECORDING DATE>` | **Stage 1 scope is 182–186 (C-2).** (Product owner, in chat, 2026-10-28: *"The intended Stage 1 scope is migrations 182–186, but this scope change must be formally recorded before execution."*) Revises the 2026-10-25 row's item (1), *"QA apply window: yes, as one batch 182 → 185."* 186 was added after that row, when PR #12 declared it. | 186 replaces the engine body 183 installs and fixes the 23514 failure; 183 must never be applied without 186 after it (manifest 183 gate, item 3). Scope does not change C-1: the batch still waits for a non-empty substrate. |

**Row 4 — `## Superseded / revised`** (§2 step 5: a revision is marked, not deleted)

> | `<RECORDING DATE>` | The 2026-10-25 row's item (1) scope *"182 → 185"* is **revised to 182 → 186** (C-2, row above). Its other conditions — the d08 fix and the nutrition-sheet error handling, both landed in PR #9 (`fc7a1c8`), and the owner's explicit go at the time — are unchanged. Item (4)'s 183 condition is **reaffirmed**, not revised (C-1). | — |

---

## 2 · Proposed `docs/MASTER_PRODUCT_DECISIONS.md` changes

§2 step 2 says *"update this document's row to `ANSWERED`."* **No row exists today** for SEQ-1, C-1 or C-2;
`OD-QAX-2` and `OD-14` likewise have no row (MPD line 62).

**ID verification (at `b74a8fc`, working tree and every local and remote ref):**

| ID | Status |
|---|---|
| `PD-A26` | highest ID **minted** in MPD §A (other series: B27, C5, D8, E8, F4, G5) |
| `PD-A27`, `PD-A28` | **not minted, but already proposed** — `V5_AUTONOMOUS_PHASE_2026-10-21_FINDINGS.md:44` option (a): *"mint `PD-A27`/`PD-A28` rows … that carry the `OD-QAX-2` and `OD-14` questions"*. **Not used here.** |
| `PD-A29` | referenced nowhere |

**No ID is assigned or reserved by this draft.** The rows below use `<ID>`. The assigning step re-checks
the register at recording time.

**Linked open question.** The same 2026-10-21 findings left open *where* answers to decisions without an
MPD row are recorded: (a) mint MPD rows, (b) `docs/adr/`, or (c) the decision log with a fixed format.
SEQ-1, C-1 and C-2 fall into the same gap. The owner chooses one home, ideally once for all five. The
options for these three:

- **(a)** add rows in **§A · Engineering decisions**, as below, with IDs assigned at recording;
- **(b)** record them only in the decision log, as was done for `OD-QAX-2` and `OD-14`.

Columns: `| ID | Decision | Blocks | Options | Recommendation | Proceed? | Owner | Wave |`

> | **`<ID>`** *(assigned at recording)* | **QA migration sequencing (SEQ-1).** Apply Stage 1 (182–186) before or after PR #14 (187–195) merges | Stage 1 window; PR #14 merge | (1) Stage 1 before merge; (2) after merge, from a separate 000–186 checkout; (3) merge, then 182–195 in one window | (1) | **ANSWERED `<RECORDING DATE>`: (1)** | Product owner | QA batch |
> | **`<ID>`** *(assigned at recording)* | **Stage 1 scope and the 183 condition (C-2, C-1).** Which migrations make up Stage 1, and when 183 may be applied | `QAX-SEC-06` (182), `QAX-SEC-01` (184), `QAX-SEC-03` (185), the engine (183/186) | scope 182→185 (2026-10-25) or 182→186; 183 unconditional (*route A*) or conditional on a non-empty substrate | — | **ANSWERED `<RECORDING DATE>`: scope 182→186; 183 conditional on `exercise_intelligence` count > 0 (not an eligibility or approval test) — batch held while it is 0** | Product owner | QA batch |

---

## 3 · Registry and progress updates that recording would require

### 3.1 `docs/MASTER_REMEDIATION_REGISTRY.md` (§2 step 3)

§2 step 3 moves findings from `BLOCKED_DECISION` to `READY_TO_REMEDIATE`. **That move does not apply
here.** C-1 *adds* a blocking condition rather than removing one. The rows to annotate, not promote:

| Registry row | Line (at `b74a8fc`) | Proposed annotation |
|---|---|---|
| `QAX-SEC-01` (P0, 184) | 3405, 3675 | QA application held: Stage 1 waits for a non-empty QA substrate (C-1, `<ID>`) |
| `QAX-SEC-03` (P1, 185) | 3406, 3676 | same |
| `QAX-SEC-06` (P2, 182 certification half) | 3412 | same |
| `WRK-06` (engine prescription; 183/186) | 262 | same; 183 conditional (C-1) |

The registry's exact status vocabulary for "authorized but held on a precondition" was **not verified**
for this draft. Confirm it before recording.

### 3.2 `docs/REMEDIATION_PROGRESS.md` (§2 step 4)

A change-log row in the existing table (the format of lines 406–411):

> | `<RECORDING DATE>` | **SEQ-1, C-1 and C-2 recorded (owner).** Stage 1 = 182–186, applied before PR #14 merges; 183 conditional on `exercise_intelligence` count > 0 (a threshold, not an eligibility or approval test), so the batch — including 184 (`QAX-SEC-01`, P0) and 185 (`QAX-SEC-03`, P1) — is **held** while the substrate is empty. No migration applied; no QA access. |

### 3.3 `supabase/expected_applied.json` — the 183 gate text

The 183 entry's gate carries an appended *"UPDATE 2026-10-25 … owner approved 'route A' in chat — 183 ships
UNCHANGED"*. Once C-1 is recorded, that text conflicts with the record. The proposed resolution is a
**dated appended note**, with the existing text left intact (that file's convention):

> `— UPDATE <RECORDING DATE> (appended): C-1 recorded — 183 is conditional on a non-empty QA exercise substrate (decision-log <RECORDING DATE>); the route A text above is not adopted where it conflicts. Stage 1 (182–186) is held while the substrate is empty.`

This is a protected edit, and `check-migration-manifest.mjs` must pass afterwards.

---

## 4 · What recording would take — none of it authorized by this draft

1. §0.1 (the consequence) and §0.2 (the threshold) are owner directions given 2026-10-28; they are **to be**
   recorded together with C-1 — not yet recorded.
2. The owner chooses where these decisions live: MPD option (a) or (b) in §2. The linked 2026-10-21 question
   should be settled at the same time.
3. The owner reviews, edits and approves the OA-2 wording in §5.
4. The owner authorizes the protected edits: the decision log, MPD (if (a)), the registry, progress, and
   the manifest gate note. Each uses the temporary exception, reverted immediately, with
   `scripts/protected-paths.json` showing no net diff afterwards.
5. Static guards are run (manifest contract, migration-wave coverage, design citations, inventory).
6. The commit is local; pushing it is a separate decision (a CI run with standing QA writes).

Until all of that is done, **SEQ-1, C-1, C-2 and the substrate threshold are directions, not recorded
decisions, and OA-2 is unsigned.** The Stage 1 packet stays held.

---

## 4a · Outstanding approvals and authorizations — consolidated, NONE GRANTED

| # | Item | Where it is defined |
|---|---|---|
| 1 | Recording SEQ-1, C-1 (with its accepted consequence), C-2 and the substrate threshold through MPD §2 | this draft §1–§3 |
| 2 | Choosing where they live: MPD rows (IDs assigned at recording) or the decision log only — with the linked 2026-10-21 `OD-*` question | §2 |
| 3 | **OA-2** — the owner adopts, edits or rejects the wording in §5 | §5; packet §1.2 |
| 4 | **OA-3** — Stage 1 window, named operator, no other activity | packet §1.2; runbook §4 |
| 5 | **OA-4** — 184's product consequence | packet §1.2; runbook §4 |
| 6 | **OA-8** — the protected manifest edit (frontier 186) | packet §1.2, §7.1 |
| 7 | **DP-1** — create, push and open the declaration PR (a QA-writing CI run) | packet §1.2, §7.1 |
| 8 | **DP-2** — merge the declaration PR into `main` | packet §1.2, §7.1 |
| 9 | The protected edits that carry items 1–3 (decision log, MPD, registry, progress, manifest 183 gate note) | §3, §4 |
| 10 | **Populating `exercise_intelligence` on QA** — the only way past C-1, and a QA write needing its own authorization | §0.1 |
| — | Not part of Stage 1, and listed so it is not assumed: Stage 2 (OA-5, OA-6, OA-7, OA-9), rollback (OA-10), merging PR #14, PD-A02, D-1, clinical sign-off, `ENGINE_WEEK_GENERATION` (stays off) | runbook §4 |

Related corrections made in the same change, outside governance: the D25 expectations at frontier 186
(packet §7.2, runbook §10) — populated, sparse and empty substrate.

## 5 · OA-2 — owner-worded approval draft — FOR THE OWNER'S REVIEW, NOT SIGNED, NOT RECORDED

**Context.** `decision-log.md:48` (2026-10-25, item 4) already records *"182 approved (Option A)"*, but as a
determination made by Claude under the owner's delegation, *"not in the owner's wording."* The owner asked
for an owner-worded version to review. The text below is a **proposal for the owner to edit**. It becomes an
approval only when the owner adopts it and it is recorded through §2. It is not signed here.

**What 182 does** *(from `expected_applied.json` 182 reason, and migration 182 itself)*: it scopes the
`exercise_certifications` definer view and the `exercise_certification(uuid)` definer RPC to
`exercise_readable(id) OR is_content_editor()`. That closes the certification half of `QAX-SEC-06`, a read of
other coaches' private and draft exercise certifications.

**The trade-off being approved** *(182's manifest gate)*: under Option A, **content editors (admin /
content manager) keep cross-owner visibility of private and draft certifications.**

**Proposed wording for the owner:**

> *"As product owner, I approve migration 182's Option A trade-off: the `exercise_certifications` view and
> the `exercise_certification` RPC are limited to exercises the caller may read, or to content editors; and
> content editors (admin and content manager) keep visibility of other coaches' private and draft
> certifications, because reviewing drafts is their job. This approves the trade-off for the QA Stage 1
> batch only. It does not approve applying the batch, which stays held under C-1, and it does not approve
> production."*

| Field | Value |
|---|---|
| Adopted wording (as edited by the owner) | ______ |
| Owner | ______ |
| Date | ______ |
| Recorded at (commit SHA on `main` + `decision-log.md:<line>`) | ______ |
| Relation to the 2026-10-25 delegated record | supersede / confirm ______ (owner's choice; §2 step 5 if superseding) |
