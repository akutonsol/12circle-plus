# V5 · Consolidated owner decision pack — the complete reconciled queue

> ## ANSWERED 2026-10-08 — eight decisions recorded
>
> | decision | ruling | recorded where | implemented? |
> |---|---|---|---|
> | **Q1** | **Ratify UTC + Monday.** The applied convention at §162.3 is now an authorization. | `METRIC-02` sub-answer, decision sheet | **already ships** (176 publishes the boundaries) |
> | **Q2** | **Publish the role split** for active-user reporting. All users, with the split shown beside the total. | `METRIC-02` sub-answer, decision sheet | **NOT YET** — authorized, not built |
> | **Q3 / `METRIC-11`** | **Option 3** — both authorities, labelled, no combined verdict. | `METRIC-11`, decision sheet | **already ships** (173/174); ingestion stays unauthorized |
> | **Q4** | **Keep design citations commit-pinned.** | here | **already ships** (65 citations resolve, guard enforces) |
> | **Q5** | **HOLD pending `Q16`.** Not to be selected independently. | here | — |
> | **Q7 / `D-1`** | **Option 4** — lazy `setUpAll`, **preserving the documented I/O-error caveat**. | here | **NOT YET** — authorized, not built |
> | **Q13** | **Option 1** — the documented trio is authoritative; `'app'` is QA seed noise. | here | no change required; **no CHECK added** |
> | **Q15** | **WITHDRAWN as an owner decision** — its premise was disproved by existing authority (`METRIC-12`). The surviving **`Elevated`** mismatch is **preserved exactly as a documented unresolved design/schema boundary**, because the design explicitly says not to resolve it. **Not resolved here.** | here, §8 | — |
>
> **`Q16` remains open and is re-presented in §9 with the consequences of Option 1 against Option 3.
> No option is chosen.**
>
> **Two of the four items I surfaced in §11 were not decisions at all** — verified against
> authoritative V5 material before being presented as open. See §15.

**Nothing was implemented for this pack.** It reconciles the carried queue against the
governing V5, programme and design sources, retrieves each decision's exact options and
evidence, states what each blocks, and recommends where the evidence supports one. **No option
is selected.**

**Design provenance.** `SCREEN-INVENTORY.md`, `BOUNDARIES.md`, `COMPONENTS.md`, `README.md` and
the six `.dc.html` screens live on the design branch at commit **`931218b`**
(`design/12circle-plus-admin-dashboard`), which is **not** an ancestor of this branch — read
them with `git show 931218b:<path>`.

---

## 0 · What the reconciliation changed, before the questions

Three corrections, all to my own bookkeeping. They are listed first because each one means a
previous pack told you something inaccurate.

| | correction |
|---|---|
| **Q14 · WITHDRAWN** | Already recorded in §197.4. I reported *"one cancelled relationship has no `cancelled_at`"*; **that reading was taken while my own `D01` fixture was live.** Measured clean (2026-10-08): **185 relationships, every one `active`, `cancelled_at` populated on zero rows** — an empty population, not a writer gap. The count drifts with QA activity; the property does not. And there is no gap: **three production paths** set it in the same write as the status (`coach_relationship_service.dart:104`, `profile_screen.dart:918`, `intake_flow_screen.dart:4188`). |
| **Q15 · PREMISE DISPROVED, a narrower question survives** | My pack carried `BOUNDARIES.md` row A's framing — *"approved screens show CRITICAL / HIGH / MEDIUM / LOW"*. **`METRIC-12` disproved that by reading all six pages: `CRITICAL` appears ZERO times**, and the uppercase `HIGH/MEDIUM/LOW` appears **only on Ecosystem**, attached to *"Harassment"*, *"Health misinformation"*, *"Spam"*, *"Off-topic"* — **moderation report priorities, a different object entirely.** `METRIC-12` is recorded `ALREADY SATISFIED` and you left it blank on 2026-10-07 with the evidence standing. **I inherited a stale framing from the design's own boundaries list instead of the verified one.** The surviving question is one value on one object — see `Q15` below. |
| **Q3 · RESTATED, it was too narrow** | I framed it as *"release METRIC-11's CI ingestion"*. **`METRIC-11` itself was never answered** (§162.7): the open question is **which authority the card shows**, not merely how to ingest. Restated below. |

**Four decisions were open in the programme record and absent from every pack** — `D-2`, `D-3`,
the `60+` bucket and `EC-01 Q2–Q5`. They are in §11, and they were found by the sweep in §12,
not by any earlier pass.

---

## 1 · Q1 · In which timezone is "today" measured?

**Exact source.** `V5_ADMIN_DASHBOARD_DATA_CONTRACT.md:98`, the `METRIC-02` row:

> **"B · OWNER — the central question** … Sub-questions the owner's answer must settle: which
> event(s) count · **the timezone the "day" is measured in** · whether a coach or partner counts
> as an "active user" or only clients."

So `Q1` and `Q2` are **two of three sub-questions of one parent**. `METRIC-02 = Option 3`
answered only the first — *"does a sign-in with no Session count as active?"* → **both bases,
shown separately.** The other two were not covered.

**What is shipped.** Migration **176 publishes the boundaries rather than choosing them**:
`day_start`, `week_start`, `month_start` and `window_timezone` are columns, and the card renders
*"Day begins 2026-10-07 00:00 UTC"*. The live value is **UTC**, because that is the database's
timezone.

**A second unruled boundary sits with it.** The decision sheet records of `METRIC-02`: *"The
weekly window is `date_trunc('week')` — an applied convention, **not** an owner ruling."*
§162.3 repeats it: *"recorded here as an applied convention, not an authorization."* In Postgres
`date_trunc('week')` starts **Monday**.

**Options.** `1` UTC, ratifying what ships · `2` a single fixed business timezone (e.g.
Europe/London), with the card restating it · `3` the viewer's local timezone · `4` per-tenant,
which needs a tenancy model that does not exist. **Week start:** `a` Monday, ratifying
`date_trunc` · `b` Sunday.

**Blocks:** nothing. The figures are correct and self-describing today. It changes what DAU
*means*, not whether it computes.

**Recommendation — `1` + `a`, i.e. ratify.** Two reasons, and neither is "it is already built":
the figures are **disclosed on the surface**, so a reader is never misled about which day was
measured; and a timezone change is a **one-line change to 176's window columns** with the
disclosure updating itself, so deferring costs nothing and ratifying loses nothing. `3` is the
only option I would argue against — a per-viewer "today" makes two operators disagree about the
same number.

---

## 2 · Q2 · Does a coach or partner count as an "active user", or only clients?

**Exact source.** The same line — `…:98`, third sub-question.

**What is shipped.** The counts are over **every** user with a Session, **no role filter**. No
filter was invented because selecting one is the business definition the contract names.

**Evidence that bears on it.** `METRIC-03` separately counts **active coaches** on the
relationship signal, and §162.4 records that on QA *"1 active coach of 135"* is **correct** —
*"of the 118 distinct `coach_id` values on active rows, only one belongs to a profile with
`role = 'coach'`; 59 of the first 60 hold `role = 'trust_operator'`"*, which is QA seed noise.
So coach activity already has its own measure on its own signal.

**Options.** `1` all users, ratifying what ships · `2` clients only · `3` all users, with the
role split published beside the total.

**Blocks:** nothing.

**Recommendation — `3`.** The split is **mechanically available** (`user_profiles.role` is on
the same population already being counted) and it is the only option that cannot be wrong: it
answers `1` and `2` simultaneously and lets the reader apply whichever definition they meant.
`1` and `2` each discard information the surface already has.

---

## 3 · Q3 · `METRIC-11` — does the release card show the V5 gate ledger or CI status?

**Restated, because my earlier framing was too narrow.**

**Exact question, from `V5_METRIC_DECISION_SHEET.md`:**

> *"does the card show the **V5 gate ledger** or **CI status**? They disagree today (CI green,
> 8 of 15 gates FAIL)"*

**Options.** `1` CI · `2` gate ledger · `3` both, labelled.

**Evidence established, verbatim from the sheet.** *"The disagreement is live and current: CI
is green 6/6 … while `RELEASE_GATES` still records failing gates. The approved card shows a
`BLOCKED` badge beside "Release 4.2.0 · staging", "Build: Passing" and "Automated QA: 1,412 /
1,418" — a gate verdict and a CI verdict **side by side**, which is evidence that the card
already contemplates both. No ingestion exists for either."*

And: *"**STILL OPEN — the one metric on this sheet you did not answer.** … Nothing was
implemented and nothing was inferred."*

**What is shipped.** Migrations **173/174** record **both halves with independent provenance** —
`ci_status`/`ci_checks_passed`/`ci_source`/`ci_recorded_at` and
`gate_verdict`/`gates_pass`/`gates_fail`/`gate_source`/`gate_recorded_at` — with a CHECK that a
verdict cannot exist without its source and timestamp, and **no `overall_status` column**. D16
asserts that a recorded disagreement **survives to the surface** (CI `Passing` beside gate
`FAIL`) with **no third combined verdict**.

**Blocks:** the *automatic* half only. The registry and the surface exist and accept recorded
verdicts; nothing ingests from CI (`CONF-D9`, and `P10` is externally constrained).

**Recommendation — `3`.** The approved card shows both side by side, the schema already shapes
both with separate provenance, and the live disagreement means `1` or `2` would **assert a
release verdict nobody authorized**. This is the one recommendation where the implementation is
already built to the recommended option *without* the ruling — so ruling `3` ratifies, while `1`
or `2` would require removing a half the design shows.

---

## 4 · Q4 · Merge the design branch, or keep commit-pinned citations?

**Facts, verified now.** `931218b` is **NOT an ancestor of `HEAD`**. The branch exists locally
and on `origin` as `design/12circle-plus-admin-dashboard`. `check-design-citations.mjs` reports
**5 citations resolved in the working tree, 60 resolved at `931218b`, 0 unresolvable anywhere,
0 commit-only without the commit named** — exit 0.

**Governing instruction.** `CLAUDE-CODE-INSTRUCTIONS.md` at that commit: *"create branch
`design/12circle-plus-admin-dashboard` … **Do not merge to main.** Do not touch existing Mobile
work."*

**Options.** `1` keep commit-pinned citations, ratifying what ships · `2` merge the design
branch into the integration branch · `3` copy the design package into this branch without
merging history.

**Blocks:** nothing. Every citation resolves and the guard enforces that.

**Recommendation — `1`.** The design package's **own instruction forbids merging**, and the
guard already proves no citation can rot: it fails on a reference that points off-branch
*without naming the commit*. `2` would contradict the handoff; `3` duplicates artifacts the
provenance file calls *"Design authority. Not modified by this handoff."* The only cost of `1`
is that a reader needs `git show`, which the citations state.

---

## 5 · Q5 · Add the Phosphor icon dependency?

**Exact source.** §15727: *"The specification names `ph-fill ph-warning-circle` from Phosphor.
**The app does not depend on Phosphor** — `pubspec.yaml` carries only `cupertino_icons` — so a
Material fill-weight equivalent is substituted. That is a substitution, not fidelity, and adding
an icon dependency is not a decision to take in passing."*

Also §11547: the handoff *"declares one shared identity — violet `#7C3AED`, Schibsted,
**Phosphor**, 4.5:1, 44px"*, and §11244 counts *"Phosphor Icons"* among what the Admin package
specifies against Helix's smaller set.

**Scope.** One icon is substituted today. The Admin icon inventory
(`docs/design/brand/icons/admin-icon-inventory.md`) is the full set the design names.

**Options.** `1` add the dependency and match the specification · `2` keep Material
substitutions and record each deviation · `3` vendor only the icons actually used.

**Blocks:** nothing. It is visual fidelity, and each substitution is recorded.

**Recommendation — none, and that is deliberate.** This is a **dependency decision for the
design system**, not for this product: §11547 records Phosphor as part of the *one shared
identity*, so the answer binds whatever consumes Helix next. It also interacts with **`Q16`** —
if the canonical Helix artefact is settled first, the icon question may be answered there rather
than here. Recommending in isolation would be the agent inference the standing constraints
forbid.

---

## 6 · Q7 · `D-1` — which reconstruction mechanism may the SEC-W1 CI negative control use?

**Exact source.** §365, reproduced with its own governance column:

| Option | Governance status | Exercises the 15 assertions |
|---|---|---|
| Delete migrations 132/133 in the workspace, restore | Authorized by precedent (`i3a11_negative_control.sh`, CI-wired) | **No — 0 of 15** |
| Isolated worktree at the pre-fix commit `07f5bfb` | Authorized by precedent (`wrk01_live_probe.sh`) | **No — 0 of 15** |
| Temporarily mutate 132/133 text, restore byte-identically | **UNSETTLED** — §8 of the closure standard says *"Never rewrite a migration in place unless the wave plan explicitly authorizes it"*; **no harness precedent exists** | **Yes — 15 of 15** |
| Change SEC-W1's `setUpAll` to lazy reads, then delete | Governed by §4:111 as a reviewed decision recorded in the evidence | **Yes**, per test, as I/O errors rather than the guard's curated `reason:` strings |

**Why the first two exercise nothing**, verbatim: *"SEC-W1 reads migration 132 inside
`setUpAll`, and in `package:test` a failing `setUpAll` means the group's tests are never run.
Deleting the migration therefore produces exactly one failure, named `(setUpAll)`, and zero of
the 15 assertions execute."*

**Blocks:** *"`QAX-SEC-08`'s fourth rung — **and nothing else**"* (§7323). Three of four rungs
hold.

**Recommendation — option 4 (lazy `setUpAll`), with a caveat I will not resolve for you.**
It is the only option that is **both governance-clean and exercises the assertions**: option 3
needs an explicit authorization against the closure standard's own prohibition, and options 1
and 2 run zero of the fifteen. The caveat is that option 4's failures surface as **I/O errors
rather than the guard's curated `reason:` strings**, so the negative control would prove the
assertions *execute and fail* without proving they fail *for the stated reason* — a weaker rung
than the other harnesses in this repository produce. Whether that is acceptable for this rung is
yours.

**Related and also open:** `D-2` and `D-3` — see §11.

---

## 7 · Q13 · `subscriptions.kind` carries `'app'`; the documented vocabulary is `coach | self_guided | ai_guided`

**Exact source.** `022_payments.sql:17-20`, the table's own comments:

```
-- 'coach'        → client subscribing to a coach (coach_id set)
-- 'self_guided'  → platform membership $29/mo (coach_id null)
-- 'ai_guided'    → platform membership $59/mo (coach_id null)
kind text NOT NULL,
```

**There is no CHECK on `kind`.** Measured on QA, **2026-10-08: 184 rows, every one
`kind = 'app'`.**

> **The row count drifts** — QA gains subscriptions from CI runs and fixtures, and it read 173
> earlier in this programme. **The evidence is the property, not the number:** *every* row
> carries `'app'`, and *every* row carries null Stripe identifiers. Re-measuring moves the
> count and not the finding.

**Two facts narrow it considerably, and neither decides it.**

1. **Every `'app'` row has a null `stripe_subscription_id` and a null `stripe_price_id`** —
   184 of 184 on both columns — so they did not arrive through Stripe.
2. **No code anywhere writes `kind = 'app'`.** `create-checkout` and `stripe-webhook` write the
   documented vocabulary and always set the Stripe identifiers.

So the `'app'` rows are **seed data, not subscriptions any code path produced**.

**Options.** `1` the comment is authoritative; `'app'` is QA seed noise · `2` `'app'` is an
intended value this repo does not yet write, and the comment is incomplete · `3` add a CHECK
once the vocabulary is ruled.

**Blocks:** any plan-level breakdown, including **churn by plan**, which `METRIC-20`'s ruling
explicitly deferred to this question. Nothing built depends on it: **no admin surface reads
`subscriptions`** except `METRIC-20`'s churn columns, which carry no `kind`.

**Recommendation — `1`, and I will not go further than that.** The evidence inside the
repository points one way: no writer, no Stripe identifiers, and the documented trio is what
both Edge Functions produce. But `2` **cannot be excluded from inside the repository** — an
`'app'` tier could be an intended product concept not yet implemented — and that is precisely
the kind of thing only you can rule. **No CHECK was added** per your instruction; adding one is
the natural consequence of `1` and remains yours to authorize.

---

## 8 · Q15 · One incident severity the design shows and the schema forbids

**My earlier framing was wrong — see §0.** `BOUNDARIES.md` row A's premise is disproved. What
survives is one value on one object.

**Exact facts.** The shipped CHECK, `143_p2_audit_incident_population.sql:70`:

```sql
CONSTRAINT audit_incidents_severity_check
  CHECK (severity = ANY (ARRAY['Critical','High','Warning','Informational']))
```

…and its comment: *"The severity enum is SPECIFIED, not chosen:
`V5_DECISION_RESOLUTION:117` — 'Severity enum also specified: Critical · High · Warning ·
Informational.'"*

**The approved Trust screen shows a fifth value on the same object.** `INC-2041` is rendered
with severity **`Elevated`** (*"INC-2041 · Elevated · AI safety · AI Guardian"*), and the
incidents overview tile reads *"Elevated · 1 elevated · INC-2041 · 3 open, 0 critical"*. §12343
records it: *"a fifth value appearing in Trust that matches neither vocabulary — recorded as
evidence, and **NOT resolved into either enum without product authority**."*

**So the design shows an incident state the schema cannot store.**

**Options.** `1` add `Elevated` to the enum · `2` the design's `Elevated` is an error; the four
specified values stand · `3` `Elevated` is a *display* grouping over existing values, not a
stored one.

**Blocks:** nothing today, and this is worth stating because it changes the urgency and not the
substance: `_severityColor` and `_severityTint` map the three coloured values and send
everything else to **neutral** — *"rendered neutrally rather than guessed into a danger
colour"* — so an `Elevated` arriving would be **legible rather than mis-coloured**. The CHECK
currently makes it unstorable, so no incident can carry it.

**Recommendation — none.** `README.md` at `931218b` instructs, in terms: *"**Do not resolve**:
attention severity labels …"*. The design package forbids me resolving it, and the enum's own
comment records it as *specified* by `V5_DECISION_RESOLUTION:117` — so changing it is amending a
specification, not filling a gap.

---

## 9 · Q16 · Which Helix artefact is canonical?

**Exact source.** `BOUNDARIES.md` row **G**: *"Admin tokens (`--adm-*`) vs Fitness Helix tiers |
Architecture question | Both documented, no merge."*

**§103 found something sharper than the row states.** Two artefacts both claim to be the
12Circle Helix theme:

| artefact | brand | status |
|---|---|---|
| in-repo Dart (`core/helix/` + `core/theme/twelve_circle_theme.dart`) | **violet `#7C3AED`**, Schibsted Grotesk | **conformance-tested in CI** |
| `/Users/dmac/Documents/projects/helix` · `src/themes/12circle.ts` | **electric lime `#9EF01A`**, Hanken Grotesk / Clash Display | its own header: *"FIRST PASS — values are meant to be tuned by design."* |

**Row G's own question is answered in substance.** §103.1 established that **eleven of eleven
shared colour roles match exactly** between the Admin tokens and the in-repo theme, along with
the typeface, both hairline strengths and the easing curve — *"This is one design system, not
two that happen to agree."* So `--adm-*` is a **normalisation of the live theme**, not a rival
tier to it.

**What remains open is narrower and outside this repository:** which artefact a future product
binds to. §103.2's own words: *"The enforced in-repo theme is the live one; the standalone lime
theme is a stale first pass … **Which is canonical is a design-system authority decision and is
not made here.**"*

**Options.** `1` the in-repo Dart theme is canonical; retire or re-tune the lime first pass ·
`2` the standalone `/helix` theme is canonical and the in-repo one is a product deviation ·
`3` both stand, with the `/helix` lime explicitly marked non-canonical.

**Blocks:** nothing in this repository — the enforced theme is live and CI holds it. It blocks
**the second product**, which is the point at which a wrong binding imports a different brand.
It also interacts with **`Q5`**.

**Recommendation — `1` or `3`, and the evidence does not distinguish them.** What the evidence
*does* establish is that `2` would be **a brand change to a shipped, CI-enforced product**: the
live app is violet and eleven colour roles, a typeface, two hairlines and an easing curve agree
across the Admin design and the in-repo theme. Between `1` and `3` the difference is whether the
lime file is deleted or labelled, which is a housekeeping preference I have no evidence to rank.

---

## 10 · The four unanswered from the metric sheet's own residue

These were recorded as *"things the rulings did not settle"* and are smaller than the questions
above. Two are already closed; two are open.

| item | status |
|---|---|
| `METRIC-02`'s **weekly window** (`date_trunc('week')` = Monday) | **OPEN · folded into `Q1`** as the week-start sub-option. Recorded as *"an applied convention, not an authorization."* |
| `METRIC-17`'s **two age sources** | **CLOSED by engineering, disclosed.** `date_of_birth` preferred, `user_profiles.age` as fallback, because dob is populated on **0 of 635** QA profiles and age on **4 of 640** — using dob alone *"would have made the panel vacuous on QA."* |
| **an age of 60 or above has no ruled bucket** | **OPEN · NEW to this pack.** `METRIC-17 = Option 2` fixed the fourth bucket as `unknown`, leaving three labelled ranges covering `[18,60)` and nothing above. No `60+` bucket was invented; `age_out_of_range` carries those rows so the four buckets plus it **reconcile exactly to `users_total`**, which D16 asserts at every boundary age. §162.3: *"whether `60+` becomes a real bucket is **narrow and still open**."* **Blocks:** nothing — the rows are counted and disclosed. **Recommendation:** none; it is a card-design choice with no evidence pointing either way. |
| `METRIC-12` · attention queue severity | **DISSOLVED BY EVIDENCE** — see §0 and §8. |

---

## 11 · Four decisions that were open in the record and in no pack

Found by the §12 sweep. None was concealed; none had been carried.

### `D-2` · Authorize remediation of **Finding A**?

**Finding A — schema-qualification blind spot — UNREGISTERED, NO ID** (§9.2):

> *"SEC-W1's `FOR ALL` detector and its `FOR UPDATE` detector both require
> `ON\s+public\.coach_team_members`. The real historical defective policy at
> `supabase/migrations/002_ecosystem_additions.sql:146-147` is written **unqualified**
> (`ON coach_team_members`), and the unqualified form is the repository's dominant style
> (approximately 3.6:1 …)."*

So the detector would **miss the real historical defect** it was written to catch.

**Blocks:** *"Finding A only"* (§7324).

### `D-3` · Authorize remediation of **Finding B**?

**Finding B — forward-supersession blind spot — UNREGISTERED, NO ID** (§9.3):

> *"SEC-W1 pins **migration 132's** text for `is_team_lead_of()` and `may_notify()`. Migration
> **134** later `CREATE OR REPLACE`s both and, because migrations apply in filename order, is
> the authoritative definition at HEAD. SEC-W1 does not read 134. **A future migration could
> weaken either helper while leaving 132 byte-identical, and SEC-W1 would still pass.**"*

Classified a *"genuine defect — the unmechanized half of §5.2's clause."*

**Blocks:** *"Finding B only"* (§7325).

**Why both need you and not me.** Remediation requires a registry ID, and **no `NEW-W1-*` ID
exists in `MASTER_REMEDIATION_REGISTRY.md` (count: 0), so no convention permits
self-allocation** (§365). I am also instructed not to modify that registry.

**Recommendation — authorize `D-3` ahead of `D-1` and `D-2`.** This is the one place in this
pack where I would argue about ordering, because `D-3` is not a reporting gap but a **live guard
blindness**: `SEC-W1` can pass while the helper it exists to protect has been weakened by a
later migration. `D-1` affects whether a negative control exercises its assertions, and `D-2`
affects whether a detector would have caught a *historical* defect — both matter less than a
guard that can be silently bypassed going forward.

### `EC-01 Q2–Q5` · what "evaluable" means

§2980: *"**blocks no phase.** `Q3`'s facts are settled — `G-14`'s audit-log conjunct has **no
requirement row**, so it can never be *met*; what is open is whether 'evaluable' means
*assessable* or *meetable*."*

**Blocks:** nothing. It is a definition inside the finding ledger, and §4-H's discipline is to
leave such contradictions unreconciled rather than pick.

### `EC-02` · the registry contradiction

Carried unchanged and **deliberately unreconciled** per §4-H: `:709` records a
`BLOCKED_DECISION` on `Q-5` while `:782` says it *"lands now"*.

---

## 12 · Verification — are there additional owner decisions hidden?

**Method.** Four passes, each stated so you can judge the coverage:

1. **The design package at `931218b`, document by document.** All seven markdown files plus the
   six screens and the build spec `.docx`. `SCREEN-INVENTORY`'s **three** requirements lists
   (*Data each page needs*, *Interactions expected*, *States designed*), `COMPONENTS.md`,
   `RESPONSIVE.md`, `BOUNDARIES.md`, `README.md`, `PROVENANCE.md`,
   `CLAUDE-CODE-INSTRUCTIONS.md`.
2. **`BOUNDARIES.md`'s seven rows**, reconciled one by one (§202). **Five were already handled;
   two became `Q15` and `Q16` — and row A's premise turned out to be disproved.**
3. **The programme definition swept for unruled markers** — *still open · remains open · not an
   authorization · applied convention · NOT DECIDED · owner decision required*. Every hit
   triaged against later sections, because this document supersedes itself as it goes.
4. **The separate registers** — `V5_METRIC_DECISION_SHEET.md`, `MASTER_PRODUCT_DECISIONS.md`.

**What the sweep closed rather than carried**, each by a later ruling I verified:

| candidate | resolution |
|---|---|
| `A13` audit-read recursion | **owner decision `R-1`** (§86), implemented |
| `A2` anonymisation recursion | **owner decision `S-2`** (§86), implemented |
| `A12` pseudonym mapping home + protection — *"UNRESOLVED — owner decision required"* at §1918 | **RESOLVED BY EXISTING AUTHORITY** → implemented in migration **146**; §19.3 answered all four of §8.20's questions |
| `phi_correction` changed-column **name set** — *"NOT DECIDED"* | **decided by `B4`** (§84.2): the names get their own column, `delta` stays NULL for that category, and only `array_agg(key)` is computed so *"no value can reach the ledger by this route"* |
| `METRIC-12` attention severity | dissolved by evidence; `CRITICAL` appears zero times |
| `D4` · `D11` · `A14` · `D-D1` | closed; **P2 reached all four rungs** (§85) and *"Nothing of `D-D1` remains open"* (§9851) |

**One register is larger than this queue and is not duplicated into it.**
`MASTER_PRODUCT_DECISIONS.md` carries **73 decisions grouped A–G by the authority required**,
with **eight on the critical path**: `PD-D08` (name a clinical owner), `PD-B01`+`PD-B02` (daily
vs weekly check-in and the canonical column family), `PD-A02` (the certification predicate),
`PD-D01` (PAR-Q policy), `PD-A17`+`PD-A10` (where the API runs, which nutrition backend is
canonical), `PD-A26`+`PD-A25` (PITR/forward-only, and what beta is), `PD-F02` (launch platform),
`PD-E07`+`PD-E08` (is production billing real, which tier ladder).

They are **catalogued, not hidden**, they are a product-programme queue rather than the V5 Admin
one, and that document states: *"**Nothing in Waves 1, 2, 3A or 3B is blocked by any decision in
this document.**"* I am instructed not to modify it, and I have not. **None of the 73 blocks the
V5 admin frontier.**

**Conclusion.** Beyond the ten questions above, the four items in §10–§11, and the 73 in the
product register, **I found no further unresolved owner decision** in the design package or the
programme records. Two things I will not claim: that the 73-decision register is itself complete,
since I did not re-derive it; and that a decision cannot be hiding in a document neither register
cites.

---

## 13 · What each decision blocks — one table

| decision | blocks | branch-local? |
|---|---|---|
| **Q1** timezone + week start | nothing; figures are correct and disclosed | — |
| **Q2** active-user population | nothing | — |
| **Q3** `METRIC-11` authority | the *automatic* half of "QA and release status (from CI)". Registry and surface exist | yes |
| **Q4** design branch | nothing; all 65 citations resolve | — |
| **Q5** Phosphor | nothing; visual fidelity, deviations recorded | — |
| **Q7 / `D-1`** | `QAX-SEC-08`'s fourth rung **and nothing else** | yes |
| **Q13** `kind` vocabulary | plan-level churn only | yes |
| **Q15** `Elevated` | nothing; unrecognised values render neutrally and the CHECK makes it unstorable | yes |
| **Q16** canonical Helix | nothing here; **the second product** | yes |
| **`D-2`** Finding A | Finding A only | yes |
| **`D-3`** Finding B | Finding B only — but it is a **live guard blindness** | yes |
| **`60+` bucket** | nothing; rows are counted in `age_out_of_range` and reconcile | — |
| **`EC-01 Q2–Q5`** | nothing | — |

**Every blocker is branch-local. No decision in this pack blocks another branch's work.**

---

## 14 · State at this frontier

No code, schema, migration, guard or test changed for this pack. Last verified state, unchanged:
live **1089/1089 across 21 suites** · Flutter **1944 / 5 skipped** · `dart analyze` **0 errors**
· nine static guards **exit 0** · QA frontier **180**, ledger `180 | 180` matching
`expected_applied.json` · CI **green on all seven jobs** at `2affe39`.

**Production was not contacted.**

---

# PART II · 2026-10-08 — the remaining unresolved decisions

Eight decisions were recorded above. Four items go forward, and **two of the four I surfaced in
§11 turned out not to be decisions at all.** The verification is in §15, and it is presented
first in each entry rather than at the end, because an item's status governs whether it belongs
in a decision pack.

---

## 15 · Verification — checked against authoritative V5 material *before* presenting as open

The instruction was to verify, not to assume. Result: **two open, two not.**

| item | verdict | the authority that settles it |
|---|---|---|
| **`D-2`** | **OPEN** | No `NEW-W1-*` ID exists in `MASTER_REMEDIATION_REGISTRY.md` (**count: 0**), no registry entry mentions the schema-qualification blind spot, the findings ledger carries neither Finding, and **SEC-W1's detectors still require `ON\s+public\.coach_team_members`** at `:71`, `:100` and `:296`. Unremediated in code and unregistered. |
| **`D-3`** | **OPEN** | Same registry result, and **`SEC-W1` mentions migration 134 zero times** — verified by count, not by reading. Unremediated in code. |
| **`60+` age bucket** | **ALREADY RESOLVED — do not re-ask** | **`METRIC-17`'s own option set.** The question was *"is the 4th bucket 60+ or unknown?"* with **`1` 60+ · `2` unknown · `3` both (5 buckets)**. A `60+` bucket was offered twice over — as option 1 and inside option 3 — and **Option 2 was chosen.** The ruling forecloses it. The decision sheet's trailing *"whether one should exist is narrow and open"* contradicted the option set it had just recorded; **corrected in the sheet.** |
| **`EC-01 Q2–Q5`** | **ALREADY ANSWERED — do not re-ask** | **§19.4 answers all four**, verbatim below. One *consequence* is outstanding and it is a documentation action, not a decision. |

### `EC-01 Q2–Q5` — the answers, verbatim from §19.4

> **`EC-01`·Q2 — NO.** A canonical's closure class does not bind an alias of a different class;
> under §8.15 each alias's substantive status **and** its evidence standard follow its own
> subject matter.
>
> **`EC-01`·Q3 — `G-14` IS EVALUABLE, AND IT EVALUATES TO NOT MET.** *"Evaluable"* means capable
> of assessment; a conjunct with no requirement row evaluates to **not satisfied**, never
> indeterminate. *Required by 13:* **a gate with an unmeasurable conjunct must never be reported
> as passed.** The missing audit-log requirement row is a **documentation gap in
> `RELEASE_GATES.md`** — recorded, **not edited**.
>
> **`EC-01`·Q4 — IT IS A PRECONDITION, AND ITS ABSENCE IS A ROW-COMPLETENESS DEFECT, NOT A
> CLOSURE DEFECT.** … **No registry edit is made.**
>
> **`EC-01`·Q5 — YES.** `QA_CLOSURE_STANDARD.md` should carry the REFERENCE-ONLY definition.
> **Recorded as a required documentation action; NOT performed — that file is outside the
> mutation boundary.**

**Q3's answer also corrects something I repeated.** §2980 said *"what is open is whether
'evaluable' means assessable or meetable"* — §19.4 **had already settled it**: *"Evaluable means
capable of assessment."* I carried the earlier line forward without checking the later one.

**One action outstanding, and it is not a decision.** `Q5`'s answer requires the REFERENCE-ONLY
alias definition to be written into `QA_CLOSURE_STANDARD.md`. I verified it is **still absent**
from that file. It was recorded *"NOT performed — that file is outside the mutation boundary"*,
so it needs **authorization to edit that file**, not a ruling on its content — the content is
already decided. **I did not edit it.**

---

## 16 · `D-2` · Authorize remediation of Finding A?

### Exact governing source — §9.2, verbatim

> ### 9.2 Finding A — schema-qualification blind spot — **UNREGISTERED, NO ID**
>
> SEC-W1's `FOR ALL` detector and its `FOR UPDATE` detector both require
> `ON\s+public\.coach_team_members`. The real historical defective policy at
> `supabase/migrations/002_ecosystem_additions.sql:146-147` is written **unqualified**
> (`ON coach_team_members`), and the unqualified form is the repository's dominant style
> (approximately 3.6:1 across `supabase/migrations/*.sql`; exact counts are method-sensitive and
> should not be cited without publishing the counting expression).

### Evidence, re-verified today

**The historical defect, verbatim** (`002_ecosystem_additions.sql:146-147`):

```sql
ALTER TABLE coach_team_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Head coach manages team"
  ON coach_team_members FOR ALL USING (coach_id = auth.uid());
```

**The detectors**, at `team_membership_lifecycle_guard_test.dart` `:71`, `:100`, `:296`:

```dart
RegExp(r'CREATE POLICY[^;]*ON\s+public\.coach_team_members[^;]*FOR\s+ALL', …)
RegExp(r'CREATE POLICY[^;]*ON\s+public\.coach_team_members[^;]*FOR\s+UPDATE', …)
```

**So the regex cannot match the defect it was written to catch.**

**On the ratio — the record told me not to cite one without publishing the expression, so here
is both.** Repo-wide, over `supabase/migrations/*.sql` with line comments stripped and the
expression `CREATE\s+POLICY[^;]*?\bON\s+(public\.)?([a-z_]+)`:

| | count |
|---|---|
| qualified `ON public.<t>` | **95** |
| unqualified `ON <t>` | **167** |
| ratio | **1.76 : 1** unqualified-dominant |

**That is not the record's ≈3.6:1**, and the record anticipated exactly this — the method was
never published, so the two numbers are not comparable. **The direction holds and the magnitude
does not.** For `coach_team_members` *specifically* the picture inverts: **7 qualified to 1
unqualified**, and that single unqualified instance **is** the historical defect. So the sharper
statement is not *"the detector disagrees with house style"* but **"the detector matches the
table's current style and misses its only historical defect."**

### Option set

The source **states no options.** The only ones available without inventing any are the two the
finding's own shape implies, plus the null action:

| option | effect |
|---|---|
| `1` **Authorize remediation** — relax both detectors to accept the unqualified form | the detector would match the real historical policy; needs a `NEW-W1-*` registry ID |
| `2` **Do not authorize** — record the blind spot and leave the detectors as they are | SEC-W1 keeps asserting the corrected definitions in 132; the historical form stays undetectable |

### What it blocks

*"Finding A only"* (§7324). It is **branch-local** and blocks no phase.

### Recommendation

**`1`, at low priority.** The defect is real and narrow: it affects whether the detector would
*recognise a historical form that no longer exists in the tree* — `002`'s policy was superseded
by 132. So the remediation improves the guard's reach over history rather than closing a live
exposure. **It should not be sequenced ahead of `D-3`** — see §17.

---

## 17 · `D-3` · Authorize remediation of Finding B?

### Exact governing source — §9.3, verbatim

> ### 9.3 Finding B — forward-supersession blind spot — **UNREGISTERED, NO ID**
>
> SEC-W1 pins **migration 132's** text for `is_team_lead_of()` and `may_notify()`. Migration
> **134** later `CREATE OR REPLACE`s both and, because migrations apply in filename order, is the
> authoritative definition at HEAD. SEC-W1 does not read 134. A future migration could weaken
> either helper while leaving 132 byte-identical, and **SEC-W1 would still pass**.
>
> **Classification:** genuine defect — the unmechanized half of §5.2's clause *"A closure that
> redefines a database object must prove it preserved every property the object carried."*

### The exact SEC-W1 / 132 / 134 evidence — each line verified today

**1 · What SEC-W1 reads.** `setUpAll` opens **one** file, and it is 132:

```dart
setUpAll(() {
  final f = File('../../supabase/migrations/132_team_membership_lifecycle.sql');
  …
  m132 = f.readAsStringSync();
  code = stripComments(m132);
});
```

`grep -c "File('"` over the guard returns **one** migration path. `grep -c 134` returns **0** —
the guard does not mention migration 134 anywhere.

**2 · What 132 defines.**

| | |
|---|---|
| `132_team_membership_lifecycle.sql:157` | `CREATE OR REPLACE FUNCTION public.is_team_lead_of(target_user uuid)` |
| `132_team_membership_lifecycle.sql:184` | `CREATE OR REPLACE FUNCTION public.may_notify(recipient uuid)` |

**3 · What 134 does to both.**

| | |
|---|---|
| `134_search_path_pin_canonical_form.sql:55` | `CREATE OR REPLACE FUNCTION public.is_team_lead_of(target_user uuid)` |
| `134_search_path_pin_canonical_form.sql:71` | `CREATE OR REPLACE FUNCTION public.may_notify(recipient uuid)` |

**4 · And nothing after 134 redefines either.** Three later migrations mention the helpers —
`135`, `140`, `141` — and **every mention is a comment**, verified line by line. So **134 is the
authoritative definition of both helpers at HEAD**, and the guard that exists to protect them
reads a file that is two migrations stale.

### Option set

The source **states no options.** Available without inventing any:

| option | effect |
|---|---|
| `1` **Authorize remediation** — SEC-W1 reads the **last** migration that redefines each helper, not a pinned one | the guard tracks the authoritative definition; needs a `NEW-W1-*` registry ID |
| `2` **Do not authorize** — record the blind spot | the guard can pass while the helper it protects has been weakened |

### What it blocks

*"Finding B only"* (§7325). **Branch-local**, blocks no phase.

### Recommendation — authorize `D-3` ahead of both `D-1` and `D-2`

This is the one sequencing argument in this pack, and it rests on a distinction between the
three that the evidence makes cleanly:

- **`D-1`** decides how a **negative control** reconstructs a defect. Its failure mode is *weak
  evidence* — three of four rungs already hold, and the fourth is about whether the assertions
  execute.
- **`D-2`** decides whether the detector recognises a **historical** form that was superseded by
  132. Its failure mode is *reduced reach over the past*.
- **`D-3`** decides whether the guard reads the **authoritative** definition. Its failure mode is
  **a guard that passes while the thing it guards has been weakened** — and it is live going
  forward: any future `CREATE OR REPLACE` of `is_team_lead_of()` or `may_notify()` is invisible
  to SEC-W1 as long as `132` stays byte-identical, **which nothing would disturb.**

The first two affect how well a defect would be *reported*. The third affects whether a defect
is *detected at all*. §9.3's own classification says the same thing in the standard's words — it
is *"the unmechanized half of §5.2's clause: a closure that redefines a database object must prove
it preserved every property the object carried."*

**Why this still needs you.** Remediation requires a registry ID, **no `NEW-W1-*` ID exists in
`MASTER_REMEDIATION_REGISTRY.md` (count: 0), and no convention permits self-allocation** (§365).
I am instructed not to modify that registry, and I have not.

---

## 18 · `Q16` re-presented — which Helix artefact is canonical

**Not chosen. Re-presented with the consequences of Option 1 against Option 3, as asked.**

### Exact governing source

`BOUNDARIES.md` at `931218b`, row **G**:

> | **G** | Admin tokens (`--adm-*`) vs Fitness Helix tiers | Architecture question | Both documented, no merge |

And §103.2: *"**The enforced in-repo theme is the live one; the standalone lime theme is a stale
first pass.** Recorded because a future consumer binding to the wrong one would import a
different brand. **Which is canonical is a design-system authority decision and is not made
here.**"*

### Evidence, re-verified today

**Row G's own question is already answered in substance.** §103.1: **eleven of eleven shared
colour roles match exactly** between the Admin tokens and the in-repo theme, plus Schibsted
Grotesk, both hairline strengths (`0.08`/`0.045`) and the easing curve
(`cubic-bezier(0.2,0,0,1)` = `Motion.emphasized`) — *"This is one design system, not two that
happen to agree."* So `--adm-*` is a **normalisation of the live theme**, not a rival tier.

**What is actually in conflict is two artefacts, not two tiers.**

| | in-repo Dart | standalone Helix |
|---|---|---|
| path | `apps/mobile/lib/core/theme/twelve_circle_theme.dart` + `core/helix/` | `/Users/dmac/Documents/projects/helix/src/themes/12circle.ts` |
| accent | **violet `0xFF7C3AED`** (`:56`) | **electric lime `#9EF01A`** (`:14`, `const ENERGY`) |
| type | Schibsted Grotesk | Hanken Grotesk / Clash Display |
| enforcement | `design_token_conformance_test.dart`, run by CI's `flutter test` | none found |
| self-description | — | *"**FIRST PASS** — values are meant to be tuned by design. **What must NOT change is the shape**: this object fills the semantic contract, nothing more."* |

**Three facts that change the shape of the decision, and were not in the earlier pack:**

1. **The lime theme is not a stray file — it is a registered, exported, built artifact.**
   `src/themes/index.ts` imports it, re-exports `twelveCircle`, and maps it into
   `themes: Record<string, Theme>`. Its registry comment: *"Add one entry per REAL product, never
   speculatively."*
2. **It is built.** `dist/themes/12circle.css` exists and **contains `#9EF01A`**. So anything
   consuming Helix's build gets lime under the name `12circle`.
3. **Helix carries three themes** — `osieri`, `12circle`, `tierstrum`.

### The option set, unchanged

| option | |
|---|---|
| `1` | the in-repo Dart theme is canonical; **retire or re-tune** the lime first pass |
| `2` | the standalone `/helix` theme is canonical; the in-repo one is a product deviation |
| `3` | both stand, with the `/helix` lime **explicitly marked non-canonical** |

### Consequences — Option 1 against Option 3

**Option 1 has two sub-forms with very different costs, and the distinction matters more than
the choice between 1 and 3.**

- **`1a` re-tune.** Port the violet/Schibsted values into `src/themes/12circle.ts` and rebuild.
  The registry entry stays, `dist/themes/12circle.css` then carries `#7C3AED`, and **nothing
  breaks**: the file's own header says the values are meant to be tuned and *"what must NOT
  change is the shape"* — re-tuning is precisely what it invites. A future product importing
  `twelveCircle` from Helix gets the live brand. **This is the only option that makes the design
  system's own build output true.**
- **`1b` retire/delete.** `src/themes/index.ts` imports, re-exports and maps `twelveCircle`, so
  deleting the file **breaks the Helix build** and removes 12 Circle from the theme registry
  entirely — which contradicts the committed structure (`core → themes → one theme per
  product`). **`1b` is not a tidy-up; it is a structural change to the design system.**

**Option 3's cost is where its marker lives.** Marking the lime file non-canonical puts the
marker in a **source comment** — and it already effectively has one (*"FIRST PASS"*). But the
artifact a consumer actually consumes is **`dist/themes/12circle.css`**, which carries `#9EF01A`
and no marker at all. So Option 3 leaves the failure mode §103.2 named — *"a future consumer
binding to the wrong one would import a different brand"* — **fully intact**, because a consumer
binds to the build, not to the comment. Its benefit is that it costs nothing now and defers to
whenever the second product actually arrives.

**The asymmetry, stated plainly:** `1a` fixes the artifact; `3` annotates the source. They differ
in *where the truth ends up*, not in how much work they are — `1a` is a values edit and a
rebuild.

**Option 2 is the one the evidence argues against**, and that is a finding rather than a
preference: the live app is violet, CI enforces it, and eleven colour roles plus a typeface, two
hairline strengths and an easing curve agree across the Admin design and the in-repo theme.
Choosing `2` would be **a brand change to a shipped, CI-enforced product**, justified by a file
that calls itself a first pass.

### Why `Q5` is held behind this

`Q5` (the Phosphor dependency) is held by your ruling, and the reason is visible in the evidence:
§11547 records Phosphor as part of *"one shared identity — violet `#7C3AED`, Schibsted,
**Phosphor**, 4.5:1, 44px"*. The icon set is a property of the **same identity** this decision
settles the home of. If `Q16` lands on `1a`, the icon question is answered in the same place for
every product; if it lands on `3`, it has to be answered twice.

### Recommendation

**None between `1` and `3` — the evidence does not separate them**, and saying otherwise would be
the agent inference the standing constraints forbid. What the evidence **does** establish, and
what I will state:

- **`2` is argued against** by eleven matching colour roles, CI enforcement, and a shipped violet
  product.
- **Within `1`, `1a` is strictly safer than `1b`** — `1b` breaks the Helix build and removes a
  registered theme.
- **`3` does not mitigate the risk §103.2 named**, because the risk lives in the build output and
  the mitigation lives in a comment.

---

## 19 · State at this frontier

**No implementation changed.** `Q2` and `Q7`/`D-1` are **authorized and deliberately not built**,
per your instruction. No CHECK was added for `Q13`. `Q15` is **not resolved**. The 73-decision
`MASTER_PRODUCT_DECISIONS.md` and `MASTER_REMEDIATION_REGISTRY.md` are **untouched**.

Records written: `V5_METRIC_DECISION_SHEET.md` — `METRIC-11` resolved, `METRIC-02`'s two
sub-answers recorded, `METRIC-17`'s stale *"narrow and open"* line corrected against its own
option set. This pack — the eight rulings, and Part II.

**Open after this pack: `Q16`, `D-2`, `D-3`** — and one documentation action awaiting
authorization to edit a file outside the mutation boundary (`EC-01·Q5`'s alias definition into
`QA_CLOSURE_STANDARD.md`).

**Production was not contacted.**

---

# PART III · 2026-10-11 — the authorization gate

> ## GATE PASSED 2026-10-11 — four selections recorded
>
> | | selection | consequence |
> |---|---|---|
> | **`D-3`** | **Option A** — track the frontier | **IMPLEMENT FIRST.** SEC-W1 verifies the authoritative helper definitions at the current migration frontier and fails if they change without corresponding guard coverage, plus a regression test proving it detects a change to 134's definitions. |
> | **`D-2`** | **Option A** — accept both forms | **IMPLEMENT AFTER `D-3`.** Detector recognizes qualified and unqualified references, fixtures for both, and proof that unrelated SQL does not satisfy the guard. |
> | **`Q16`** | **Option 3** — preserve both | **NO THEME CHANGES.** Both artifacts and their current distinction stand. The **authority question stays open by design** — Option 3 defers it rather than answering it — so **`Q5` (Phosphor) remains on hold behind it.** |
> | **`EC-01 Q5`** | **APPROVED** | A narrowly scoped edit to `QA_CLOSURE_STANDARD.md` recording the already-decided REFERENCE-ONLY alias definition. No unrelated policy change, no alteration to the decision, no broadening of the mutation boundary. |
>
> **`EC-02` not reconciled. No master register modified.** The sections below record the gate as
> it was presented, and remain the authority for each option's exact wording.

**The gate as presented.** Four selection lines arrived unfilled —
`Owner selection: A / B / C` (×2), `Owner selection: 1a / 1b / 3 / 2`, and
`Owner authorization: Approve / Deny` — and execution rules 3 and 5 are conditional on them
(*"Once authorized, implement D-3 first"*, *"Make the authorized documentation edit only if
approved"*). **Nothing in §16–§18 was implemented.** The option sets below supersede my
two-option framings, which were narrower.

## 20 · `D-3` · SEC-W1 authoritative migration coverage — **awaiting selection**

| option | as presented |
|---|---|
| **A — recommended** | Update SEC-W1 so it **verifies the authoritative helper definitions at the current migration frontier** and fails if those definitions change without corresponding guard coverage. **Add a regression test proving the guard detects a change to the migration 134 definitions.** |
| **B** | Explicitly cover migrations **132 and 134**, with a test that demonstrates **why both references remain necessary**. |
| **C** | Defer remediation and leave the finding visibly open. |

**Sequencing as presented: prioritize this first.** My §17 evidence stands behind that, and it is
re-verified: SEC-W1's `setUpAll` opens exactly one migration (132); `132:157/:184` define the two
helpers; **`134:55/:71` `CREATE OR REPLACE` both**; `135`/`140`/`141` mention them **only in
comments**; and the guard mentions 134 **zero times**.

**A is the stronger of A and B on the evidence**, and the difference is worth stating because it
is not stylistic: **B pins two migrations, which is the same defect one migration later** — a
future `135_*` redefinition would be invisible to a guard that pins 132 and 134 exactly as it is
invisible to one that pins 132. **A tracks the frontier**, so it does not need amending the next
time a helper is redefined. A's regression test — *"proving the guard detects a change to the
migration 134 definitions"* — is what makes the frontier claim falsifiable rather than asserted.

## 21 · `D-2` · the policy detector's unqualified-reference blind spot — **awaiting selection**

| option | as presented |
|---|---|
| **A — recommended** | Make the detector recognize **both qualified and unqualified** table references, add **regression fixtures for both forms**, and **verify that unrelated SQL does not satisfy the guard**. |
| **B** | Keep the detector unchanged and document the known historical blind spot. |
| **C** | Defer remediation while retaining the finding as open. |

**Sequencing as presented: after `D-3`.**

The third clause of A is the one that matters most and it was not in my framing: *"verify that
unrelated SQL does not satisfy the guard."* Relaxing a regex to accept `ON <table>` as well as
`ON public.<table>` **widens** it, and a widened detector can start matching policies on other
tables — so the fixture set has to prove both that the historical form **is** caught and that
nothing else newly is. That is the difference between loosening a guard and extending it.

## 22 · `Q16` · Helix theme authority — **awaiting selection**

| option | as presented |
|---|---|
| **1a** | Retune the lime theme values **while preserving the registered theme and its structural contract**. |
| **1b** | Delete the lime theme, **acknowledging that this changes registered theme structure and may break the Helix build**. |
| **3 — recommended, conservative** | **Preserve both existing artifacts and their current distinction; make no theme changes** until the authority question is resolved. |
| **2 — not recommended** | Make lime the brand theme. Conflicts with the shipped violet product and the existing CI-conformance evidence. |

**A caution I accept, and a correction to how I argued §18.** *"Do not infer brand authority from
build success alone."* That is fair. My §18 leaned on `dist/themes/12circle.css` containing
`#9EF01A`, and the most that observation supports is **what a consumer who imports the built
artifact would receive** — it is evidence about a *binding risk*, not about which theme holds
brand authority. Brand authority is not established by a file building successfully, and I should
not have let the build output carry as much weight as it did. **Option 3's rationale — preserve
the current state rather than invent a design decision — does not depend on resolving that
question, which is precisely its merit.**

**`Q5` (Phosphor) remains on hold behind this**, as ruled.

## 23 · `EC-01 Q5` · documentation authorization — **awaiting Approve / Deny**

**Requested:** a narrowly scoped edit to `QA_CLOSURE_STANDARD.md` to record the
**already-decided** `EC-01 Q5` alias definition. **No unrelated policy change, no alteration to
the underlying decision, no broadening of the mutation boundary.**

Verified unchanged: the content is decided (§19.4 — *"YES. `QA_CLOSURE_STANDARD.md` should carry
the REFERENCE-ONLY definition"*), the file **still carries no alias definition**, and the action
was recorded *"NOT performed — that file is outside the mutation boundary."*

## 24 · Verification at this gate — the actual commit

Per execution rule 6, **prior green CI is not carried forward as proof of this commit**:

| | |
|---|---|
| tested commit | **`d0ac619`** — local `HEAD` and `origin/reconcile/12circle-integrated` agree |
| CI | **success** |
| nine static guards | **exit 0**, re-run at this commit |
| implementation changed | **none** — §16–§23 are records only |

One observation while checking, recorded because it is not mine: `9dc7515` appears in recent CI
runs and is **not on this branch** — it is on `main`, from the scheduled **Supabase Keep-Alive**
workflow. A new remote branch `workstream/12c-plus-website` also appeared. Neither touches this
work; neither was acted on.

**`EC-02` was not reconciled and no master register was modified.**

**Production was not contacted.**

---

# PART IV · 2026-10-11 — the authorized work, implemented

`D-3` first, `D-2` second, the documentation edit third — the order the gate set.

## 25 · `D-3` implemented · Option A

**SEC-W1 now resolves the definition in force** instead of reading a pinned file. Three
resolvers over the migration corpus in filename order — which is apply order: `definersOf`
(every migration redefining a helper), `authoritativeOf` (the last one), and three property
checks written as **pure functions over a body** so a mutation can be fed to them.

**The resolvers found more than Finding B recorded.** The finding named 132 and 134.
Measured: **`is_team_lead_of` is redefined by three migrations — `102`, `132`, `134` — and
`may_notify` by four — `118`, `129`, `132`, `134`.** Both are authoritative at 134. A longer
supersession chain than the finding described is itself the argument for resolving the frontier
rather than listing files.

**No live regression was found, and that is worth stating plainly.** 134 *preserves* both Wave 1
properties — `is_team_lead_of` carries `AND t.status = 'active'` (`134:67`) and `may_notify`'s
team arm carries `WHERE t.status = 'active'` (`134:88`), both with their D1(ii) comments. So
`D-3` was a guard-coverage gap exactly as classified, not a hidden weakening.

**The coverage ratchet** is the mechanism the ruling asked for: the definer set for each helper
is recorded, so a new redefinition fails the guard until somebody records it — which is the
moment to re-check the properties against the new definition in force.

**The 132 assertions are kept**, and they prove a different thing: that Wave 1's own migration
still says what it said. Reverting 132 and weakening 134 are two separate regressions, and the
guard now has an assertion for each.

**The regression test the ruling required** mutates the **real** text of 134 — not a toy string
— and requires each check to fail: the ACTIVE predicate dropped from `is_team_lead_of`; dropped
from `may_notify`'s team arm only, leaving the other arms intact; `search_path` unpinned on
either helper; and a synthetic later migration that **moves the frontier, trips the ratchet, and
fails the property checks it was hiding from**. A `setUpAll` control asserts the unmutated
baseline passes first, because a mutation proves nothing against an already-broken baseline.

## 26 · `D-2` implemented · Option A

**Both qualification forms, at four sites**, through one word-bounded pattern builder
(`policyOn`) and one policy-scoped target scan (`policyTargets`).

**Why `\b` is not optional:** without a word boundary, `(?:public\.)?coach_team_members` also
matches **`coach_team_members_archive`**, and the guard would start failing on a table it has no
business judging. Widening a detector is not free, and two negative fixtures pin that case.

**One site was deliberately NOT widened, and the measurement is why.** The scope check over 133
extracts table names from `ON\s+public\.([a-z_]+)`. Widened to make `public.` optional, a bare
`ON` scan over 133 returns **`{D, TABLE, public.coach_team_members}`** — `TABLE` from
`COMMENT ON TABLE`, `D` from a decision reference. The qualified-only form was accidentally
protected from that, so widening it would have traded a blind spot for a false alarm. The
unqualified gap is closed instead by `policyTargets`, scoped to `CREATE`/`DROP POLICY` only,
which cannot match a comment or a foreign key.

**The third clause of Option A is the one this group is built around** — *"verify that unrelated
SQL does not satisfy the guard."* Fourteen fixtures: four positive shapes (qualified,
unqualified, newline-before-`FOR`, mixed case), **the real 002 defect read from disk** rather
than retyped so the fixture cannot drift from the file it quotes, six negative shapes (different
table, two longer prefix-sharing names, different command, a `DROP` rather than a `CREATE`, a
`GRANT`), a commented-out policy, and a check that the `FOR ALL` and `FOR UPDATE` detectors stay
**distinct** so the two findings cannot become indistinguishable.

**SEC-W1: 14 tests → 43.**

## 27 · `EC-01 Q5` implemented · the authorized documentation edit

`QA_CLOSURE_STANDARD.md` now carries the REFERENCE-ONLY definition, in §4 — *"What does not
close a finding"* — which is where a rule about what a closure does **not** discharge belongs.

**Narrow, and measurably so: 23 insertions, 0 deletions.** Nothing existing was altered. One
prohibition row, and a §4.1 carrying the decided text verbatim from §8.15 and its §19.4
extension, labelled as recording an existing decision rather than making one. **No unrelated
policy changed, the underlying decision is untouched, and the mutation boundary is not
broadened** — one file, one section.

## 28 · `Q16` · nothing implemented, by the ruling

Option 3 preserves both artifacts and their current distinction. **No theme file, registry entry
or build output was touched**, and the authority question stays open by design — Option 3 defers
it. **`Q5` (Phosphor) therefore remains on hold.**

## 29 · Verification — the actual tested commit

Per execution rule 6, prior CI is not carried forward.

| | |
|---|---|
| Flutter | **1972 passed / 5 skipped** (1944 → 1972) |
| `dart analyze` | **0 errors** |
| SEC-W1 | **43 / 43** |
| nine static guards | **exit 0** |
| migration frontier | **180**, unchanged — no schema touched |
| implementation files changed | **one test file**; two documents |

CI for the commit carrying this work is reported in the final summary, not inferred from an
earlier run.

**`EC-02` not reconciled. No master register modified. Production was not contacted.**

---

# PART V · `D-1` implemented — P1's fourth rung

**Authorization.** `Q7`/`D-1` **= Option 4** was ruled on 2026-10-07 and left unbuilt only
because that message said not to implement yet. This turn's execution rule 7 — *"resume
autonomous work across independently executable branches"* — makes it the next authorized,
unblocked item, and it closes *"`QAX-SEC-08`'s fourth rung — and nothing else"*.

## 30 · The lazy read, and why the other three options exercised nothing

The guard read migration 132 in an **eager `setUpAll`**, and in `package:test` a failing
`setUpAll` means **the group's tests are never run** — so deleting 132 produced exactly one
failure, named `(setUpAll)`, with **zero of twelve assertions executed**. §365 recorded that as
`0 of 15` for both delete-and-restore and the isolated-worktree option, and the third option —
mutating 132's text in place — is **UNSETTLED** against §8 of the closure standard
(*"never rewrite a migration in place unless the wave plan explicitly authorizes it"*).

Reading on first touch makes each of the twelve fail on its own. **Measured: 13 individual
failures** where there was one.

**The caveat is preserved, not engineered away.** A missing file throws
`PathNotFoundException` — the Dart 3 `FileSystemException` subtype — so the failures arrive as
**I/O errors rather than the guard's curated `reason:` strings**. No wrapper was added to
re-brand them. **What the control proves: the assertions execute and fail. What it does not
prove: that each fails for the reason it states.** That is a weaker rung than the
mutation-based controls elsewhere here, and it is the rung that was authorized.

Addendum A's own `setUpAll` (migration 133) is untouched — `D-1` names the 132 read, and a
control that deletes 132 does not reach 133.

## 31 · What the harness found that I had assumed wrong

My first version required *"Addendum B must not fail"*, on the reasoning that D-3 reads 134 and
is therefore independent of 132. **The run disproved half of that**, and the correction is the
more informative control:

* **D-3's property tests DO survive** — the definition in force is in 134, and `authoritativeOf`,
  the ACTIVE checks and the `search_path` check all passed with 132 deleted. That independence is
  exactly what D-3 bought.
* **D-3's coverage ratchet correctly FAILS** — the definer set really did change, from
  `[102, 132, 134]` to `[102, 134]`. A ratchet that stayed green when a defining migration was
  deleted would not be a ratchet.

So the harness now requires **both**: the property tests to pass *and* the ratchet to have run.
Conflating them would have hidden whichever one broke.

**A second defect, in the harness's own check.** It asserted the failure text contained
`FileSystemException` and reported *"no FileSystemException in the output"* against a tree
failing exactly as designed — because Dart 3 throws the **`PathNotFoundException`** subclass and
its `toString()` names the subclass. The check was wrong about the string while the caveat it
guards was right about the substance. Both names are accepted now, and the specific one is named
in the message so a future change of shape is legible rather than silent.

## 32 · Evidence

`secw1_negative_control.sh`, following the house convention of `ec23`/`wrk02`/`ec03`: baseline
passes → migration deleted → **13 individual failures (≥ 12 required)**, the I/O shape asserted,
the `(setUpAll)` trap asserted **absent**, D-3's property tests asserted to have **passed** and
its ratchet to have **run** → restored **byte-identically** (`git diff --quiet`) → the whole
guard passes again. **Wired into CI's existing negative-control job**; no new job, credential or
network access.

SEC-W1 **43/43** · Flutter **1972 / 5 skipped** · `dart analyze` **0 errors** · nine static
guards **exit 0** · migration frontier **180**, untouched.

**Production was not contacted.**
