# V5 — METRIC DECISION SHEET

**Source: `docs/V5_OWNER_DECISION_PACK.md` §C.3, read verbatim. 12 decision IDs across 11 cards —
Revenue carries two.** Prepared 2026-10-07 against QA frontier 170.

> **STATUS: RESOLVED 2026-10-07, except METRIC-11.** The owner ruled ten IDs plus the METRIC-18
> producer and the METRIC-06b calculation. Each response field below now carries the ruling and the
> surface that implements it. **METRIC-11 was not answered and nothing was built for it.** Two
> corrections to this sheet's own evidence are recorded inline (METRIC-14, and the METRIC-17 age
> source), and one discrepancy is reported rather than reconciled (METRIC-06b).

**No option is selected and no answer is inferred.** Options are quoted exactly as §C.3 states them. The
*Evidence established* column is what this programme has since proven at source or measured live on QA; it is
there to make the choice cheaper, not to make it for you.

**Two IDs are not open.** `METRIC-12` resolved by evidence and `METRIC-18`'s *meaning* is already ruled —
both are shown so the sheet is complete, and neither needs an option.

---

## The four cards that need no decision

Already determined and **producers live**, verified this run: **Total users** → `admin_user_overview` ·
**Recent admin activity** → `admin_audit_events` · **Security** → `admin_security_events` ·
**AI Guardian (read-only)** → `governance_policy` + `guardian_state`.

---

## METRIC-02 · Active users / DAU

**Question (§C.3).** *"does a **sign-in with no Session** count as active?"*
**Options.** `1` Session only (`product-bible` §5: Session = one day's workout) · `2` sign-in counts ·
`3` both, shown separately

**Evidence established.** No rollup or producer exists. `workout_sessions` holds **9 rows** on QA and is the
only candidate for "Session". Sign-in events reach `audit_events` as category `authentication`, which your
`B-1` ruling already placed in the Security area — so option 2 or 3 would read a population the Admin layer
can already see. The approved card shows **DAU / weekly / monthly plus a month-on-month delta**, so whichever
basis you pick must support three windows.

**RESOLVED 2026-10-07 · METRIC-02 = Option 3** — both bases, shown separately. Shipped as
`admin_activity_overview` (172). The two bases are gated SEPARATELY: Session on `Users·view`, sign-in on
`Security·view` per ruling `B-1`, so a Users-only role receives NULL rather than 0.

**THE TWO REMAINING SUB-QUESTIONS ARE NOW ANSWERED.** `V5_ADMIN_DASHBOARD_DATA_CONTRACT.md:98` recorded
three sub-questions the owner's answer had to settle — *"which event(s) count · the timezone the 'day' is
measured in · whether a coach or partner counts as an 'active user' or only clients."* Option 3 answered
only the first. The other two:

- **RESOLVED 2026-10-08 · window boundaries = UTC, week starts Monday.** This **ratifies what ships**:
  migration 176 already publishes `day_start` / `week_start` / `month_start` / `window_timezone` as
  columns and the card renders *"Day begins … 00:00 UTC"*. `date_trunc('week')` — Monday in Postgres —
  was recorded at §162.3 as *"an applied convention, not an authorization"*; **it is now an
  authorization.**
- **RESOLVED 2026-10-08 · the active-user population is ALL users, with the role split PUBLISHED beside
  the total.** Not clients-only and not an unexplained aggregate: the split is to be shown, so a reader
  can apply either definition. **IMPLEMENTED 2026-10-11 · migration 181** — six `*_by_role` columns on
  `admin_activity_overview`, three per basis, each carrying the SAME `admin_can` gate as the total it
  splits. Published as role→count **maps**, not as named `clients`/`coaches`/`partners` buckets:
  collapsing 142's seven roles would be a metric definition no decision issued, and it would foreclose
  the very choice this ruling preserves. `no_profile` (no `user_profiles` row — legitimate for sign-ins
  per 142:113) and `unrecorded` (row exists, `role` NULL) are kept distinct. Each map sums EXACTLY to its
  total, which is the assertion that makes it a split rather than a number sitting nearby — proved live
  by **D22 (25/25)**, including a moved population so the equality is not two zeroes agreeing.

---

## METRIC-03 · Active coaches

**Question.** *"'this month' = **calendar month** or **trailing 30 days**? (the approved screens use both)"*
**Options.** `1` calendar · `2` trailing 30d

**Evidence established.** `coach_client_relationships` holds **117 active** rows — the intersection the card
needs ("of 164 · 23 with no client this month") is computable today; only the window is undecided. The
approved screens genuinely use both phrasings, which is why the record calls this narrow rather than open.

**RESOLVED 2026-10-07 · METRIC-03 = Option 1** — calendar month. Shipped on `admin_user_overview` (172) as
`coaches_active_this_month` / `coaches_no_client_this_month`, which partition `coaches_total` exactly. The
window is NOT computed on `activated_at` (NULL on 117 of 118 live active rows, so it would be vacuous).

---

## METRIC-05 · Wellness partners

**Question.** *"the **approval state machine** — '9 awaiting approval' implies states the schema does not
have"*
**Options.** `1` define now (needs the state list from you) · `2` drop the sub-count, show total only ·
`3` defer the card's second line to an `A11` state

**Evidence established.** Confirmed twice over: **no approval-state column exists** on `user_profiles`, and
**`role='vendor'` returns 0 rows on QA** — so the card has neither a state machine nor any partner data.
`PD-A19` (role-assignment governance) is the nearest existing decision and is itself open. Option 1 needs the
state list; the vocabulary must come from you, as with `approval_status` and `events.status`.

**RESOLVED 2026-10-07 · METRIC-05 = Option 2** — total only, no sub-count. **No code was needed:**
`admin_user_overview.vendors_total` (166) already serves it. No approval state machine was invented.

---

## METRIC-06a · Revenue — currency

**Question.** *"**`PD-C03` currency** — `'usd'` is hardcoded everywhere; the card shows **£**"*
**Options.** `1` record single-currency USD + explicit FX for display · `2` multi-currency (large)

**Evidence established.** Verified live: `payments.currency` is `text NOT NULL DEFAULT 'usd'`. `PD-C03` is an
**open register row**, not a new question — it is listed here because the card cannot render until it closes.
Your standing instruction keeps **GBP/£ as the Admin display currency with explicit FX**, which option 1
satisfies without touching billing.

**RESOLVED 2026-10-07 · METRIC-06a = Option 1** — single-currency USD plus explicit FX. Shipped as the
`fx_rates` record and `admin_revenue_overview`'s `fx_usd_gbp_rate` / `fx_as_of` / `fx_source` (171). The
table starts **empty** and no vendor feed was introduced; with no rate recorded the columns are NULL and
the card renders an `A11` state rather than a conversion nobody authorized.

---

## METRIC-06b · Revenue — gross vs commission

**Question.** *"is 'coaching' **gross** or **platform commission**?"*
**Options.** `1` show all three (gross / commission / net) — *"your earlier direction already approved this
decomposition"* · `2` gross only · `3` net only

**Evidence established — the decomposition is already ruled.** Direction **`I`** (ledger `:12344`), verified
at source: *"Admin must distinguish **gross coaching revenue · platform commission · net/platform revenue**.
`marketplace_commission_rate` (0.10, `038:14`) is the commission input. **Calculation and source definitions
must be explicit before implementation; no monetary value is fabricated.**"*

So option 1 is the recorded direction. **What is still owed is the calculation itself**, which the direction
demands and `COWORK` §8 forbids an agent inventing. QA holds **1 payment** and **116 subscriptions**, and
`subscriptions` carries no monetary amount — so a source definition is required before any figure exists.

**RESOLVED 2026-10-07 · METRIC-06b = Option 1** — gross, commission and net all shown.
**RESOLVED 2026-10-07 · the calculation is quoted verbatim in 171's header** and implemented clause by
clause. Qualifying coaching payments are `kind IN ('coach','package')` — the two kinds in the
`create-checkout/index.ts:52` vocabulary by which a member pays a coach; `coach_plan`, `self_guided`,
`ai_guided` and `event_ticket` are excluded and **counted** in `excluded_non_coaching`. Commission uses
each payment's own recorded `commission_rate` (038:23); rows missing it are counted in
`commission_rate_missing` and given **no substituted rate**.

> **ONE DISCREPANCY IS OPEN AND WAS NOT RECONCILED.** Your formula applies
> `marketplace_commission_rate` to all gross coaching revenue; `038:14` scopes that column to a
> *"MARKETPLACE-acquired client's coaching payments"* and `client_source` is commented as the field that
> *"drives commission"*. Using each payment's recorded rate makes the shipped figure correct under **both**
> readings, so nothing is blocked — but whether `coach_invited` payments belong in the denominator, and
> whether historical rows should be back-filled, remains yours to rule. See §162.2.

---

## METRIC-11 · QA & release

**Question.** *"does the card show the **V5 gate ledger** or **CI status**? They disagree today (CI green,
8 of 15 gates FAIL)"*
**Options.** `1` CI · `2` gate ledger · `3` both, labelled

**Evidence established.** The disagreement is live and current: CI is **green 6/6** on `8bc17cc` while
`RELEASE_GATES` still records failing gates. The approved card shows a **`BLOCKED` badge** beside
*"Release 4.2.0 · staging"*, *"Build: Passing"* and *"Automated QA: 1,412 / 1,418"* — a gate verdict and a CI
verdict **side by side**, which is evidence that the card already contemplates both. No ingestion exists for
either.

~~**STILL OPEN**~~ **RESOLVED 2026-10-08 · METRIC-11 = Option 3** — both, labelled.

The card shows **both authorities, separately labelled, with no combined verdict.** Already shipped to
this shape before the ruling: migrations **173/174** carry each half with **independent provenance** —
`ci_status` / `ci_checks_passed` / `ci_source` / `ci_recorded_at` beside `gate_verdict` / `gates_pass` /
`gates_partial` / `gates_fail` / `gate_source` / `gate_recorded_at` — under a CHECK that a verdict cannot
exist without its own source and timestamp, and **deliberately no `overall_status`, no `is_blocked`, no
single badge column** (`173:28`). D16 asserts that a recorded disagreement **survives to the surface**
(CI `Passing` beside gate `FAIL`) with no third verdict synthesised.

**The ruling ratifies the shipped shape; it authorizes no new surface.** The CI **ingestion** half remains
separate and unauthorized — `CONF-D9`, and `P10` is externally constrained — so the registry accepts
recorded verdicts and nothing reads CI automatically.

---

## METRIC-12 · Attention queue severity — **RESOLVED BY EVIDENCE, no option needed**

**Question as recorded.** *"Approved UI shows `CRITICAL/HIGH/MEDIUM/LOW`; the shipped, V5-specified CHECK is
`Critical/High/Warning/Informational` (`143:70`)."*

**Evidence established — the premise was wrong and the conflict does not exist.** Reading all six approved
pages: **`CRITICAL` appears zero times.** The attention queue renders **`Critical`** and **`High`** — title
case, *the shipped enum* (*"Critical · Security · 14 min ago · Open"*). The uppercase `HIGH/MEDIUM/LOW`
appears **only on Ecosystem**, attached to *"Harassment"*, *"Health misinformation"*, *"Spam"*,
*"Off-topic"* — **moderation report priorities, a different object entirely.**

**No enum change, no display-map, no implementation.** Recorded as `ALREADY SATISFIED` (§158).

**LEFT BLANK 2026-10-07 — the evidence stands.** METRIC-12 remains dissolved: `CRITICAL` appears zero
times; the attention queue uses the shipped `Critical`/`High` enum.

---

## METRIC-13 · Ecosystem activity — "pods"

**Question.** *"what a 'pod' is (`86 pods`) — `accountability_pods` exists but the count does not match"*
**Options.** `1` `accountability_pods` · `2` `community_groups` · `3` something else you define

**Evidence established.** Both candidates exist and **neither matches**: `accountability_pods` holds **1 row**
and `community_groups` **5** against the design's *"86 pods"* — though the screens carry *"sample
design-state data"*, so counts cannot settle it either way. The design uses *pods* as a Community unit
(*"Community — 86 pods · 1,940 posts"*) and separately names *"Pod-level challenges"*. Your `B-18` ruling
confirmed `accountability_pods` is readable by any authenticated member.

**RESOLVED 2026-10-07 · METRIC-13 = Option 1** — a pod is an `accountability_pods` row. Shipped as
`admin_community_overview.pods_total` (172). `community_groups_total` is reported **alongside** it as a
distinct figure and is asserted never to be merged into the pod count.

---

## METRIC-14 · Events / community — "attendance"

**Question.** *"which '74% attendance' means"*
**Options.** `1` registrations ÷ capacity · `2` attended ÷ registered (**no attendance column exists**) ·
`3` bookings ÷ capacity

**Evidence established, and it bears on the choice.** The approved design renders *"Registrations · 30 d —
1,640"* and *"Attendance rate — 74%"* as **two separate figures**, and an individual event as *"88 / 120"* —
which **argues against option 1**, since the design already shows registrations and attendance as different
numbers. A member profile shows *"Events attended — 3"*. Confirmed live: `event_registrations` has **no
`attended` column** (2 rows on QA), so option 2 requires a new column and a capture mechanism.

**RESOLVED 2026-10-07 · METRIC-14 = Option 2** — attended ÷ registered. Shipped on
`admin_events_overview` (172).

> **CORRECTION TO THIS SHEET'S OWN EVIDENCE, AND THE ERROR WAS MINE.** The note above — *"no attendance
> column exists"*, and that option 2 *"requires a new column and a capture mechanism"* — is **false**.
> `event_registrations.checked_in_at` exists (migration 138) and **is already written** by
> `vendor_service.dart:90-93` on check-in. Option 2 required **no new column and no new capture
> mechanism**. I reported the absence of a column named `attended` as the absence of the capability. You
> chose this option believing it carried a build cost it does not carry. See §162.1.

---

## METRIC-16 · Installs

**Question.** *"`PD-A24` = `C` forecloses an **analytics vendor**; is reading **our own** store consoles
that? Console credentials are also an **account boundary**"*
**Options.** `1` not a vendor — authorize console ingestion · `2` it is — card renders `A11` empty ·
`3` manual periodic entry

**Evidence established.** No ingestion, no credentials, no table. The approved card fixes an **Apple / Google
Play split**. `PD-A24` is ruled `C` and this question tests its edge — the record states the matter *"is not
settled either way"*. Option 1 additionally requires store-console credentials, which is an account boundary
only you can cross.

**RESOLVED 2026-10-07 · METRIC-16 = Option 2** — reading our own store consoles *is* the vendor boundary
`PD-A24` forecloses, so the card renders `A11` empty. **Decided, nothing implemented:** no ingestion, no
credentials, no table. The account boundary was not crossed.

---

## METRIC-17 · Age demographics

**Question.** *"is the 4th bucket **60+** or **unknown**?"*
**Options.** `1` 60+ · `2` unknown · `3` both (5 buckets)

**Evidence established.** The approved panel labels exactly **three** buckets — `18–30 years` (46%),
`30–45 years` (32%), `45–60 years` (18%) — plus an **unlabelled 4%** remainder. The labelled edges
**overlap** (30 and 45 each appear in two buckets), so half-open intervals are required whichever way you
rule. Confirmed live: **`date_of_birth` is populated on 0 of 635 QA profiles**, so the aggregate has a column
but no data.

**RESOLVED 2026-10-07 · METRIC-17 = Option 2** — the fourth bucket is `unknown`. Shipped on
`admin_user_overview` (172) as half-open `[18,30) [30,45) [45,60)` plus `age_unknown`. Two things this
sheet did not settle are recorded rather than invented (§162.3): the age source is `date_of_birth`
**preferred** with `user_profiles.age` as fallback — this sheet cited only the former, which is populated
on 0 rows while the latter has 4, so dob alone would have made the panel vacuous; and **an age of 60+ has
no ruled bucket**, so those rows go to `age_out_of_range`, a reconciliation column that keeps them from
being silently dropped. **No `60+` bucket was invented.**

> ~~*Whether one should exist is narrow and open.*~~ **CORRECTED 2026-10-08 — that line was wrong, and
> this sheet's own option set is why.** The question put to the owner was *"is the 4th bucket 60+ or
> unknown?"* with **option `3` = both (5 buckets)** — so **a `60+` bucket was explicitly on the table**,
> alongside `unknown`, and **Option 2 was chosen over it.** The ruling therefore forecloses a `60+`
> bucket; it is **resolved, not open.** What `age_out_of_range` does — carry both the under-18 and the
> 60-and-over rows so the four buckets plus it reconcile exactly to `users_total` — stands as the ruled
> consequence. (It **merges two populations** into one reconciliation figure; separating them would be a
> new request, not an open question.)

---

## METRIC-18 · Impressions — **MEANING ALREADY RULED; producer is the open half**

**Question.** *"**which impression** — store-listing, marketing, or in-app?"*
**Options.** `1` in-app · `2` store-listing · `3` marketing · `4` card renders `A11` empty

**Evidence established — direction `K` already defines it.** Ledger `:12345`, verified at source: impressions
are ***"eligible content renders/views, held distinct from reach · unique viewers · clicks · engagement ·
sessions"***. That **supersedes** the earlier reconciliation line (`:12134`) saying the term appears in no V5
source, which predates it. So the meaning is **closed** and matches option 1.

**What remains is the producer.** Confirmed live: **no impressions table exists** and nothing emits a render
event. **`flagcdn.com` appears only in documentation** — no shipped reference in `apps/` or `supabase/` — so
there is no egress today and none was introduced.

**RESOLVED 2026-10-07 · N** — no in-app render event is built. The card renders `A11` empty.
**Decided, nothing implemented.**
**LEFT BLANK 2026-10-07** — the meaning ruled by direction `K` stands.

---

## METRIC-19 · Notifications placement — *new, from the design package's own boundary list*

**Question.** `BOUNDARIES B`: the build spec names a **Notifications Overview** group; **no corresponding
area exists on the approved Dashboard**, and `Notifications` is **not** one of the 17 matrix areas.
**Options.** `1` place it under Operations · `2` place it on the Dashboard · `3` out of scope for V1

**Evidence established.** The requirement is kept by the design package and its placement explicitly left
undecided. A `notifications` table exists and ships. `CAP-2` additionally records that it has **no
sent/delivered/failed/pending state** — it records `read`, i.e. engagement only — so delivery telemetry would
be a separate extension.

**RESOLVED 2026-10-07 · METRIC-19 = Option 3** — out of scope for V1. Nothing authored.

---

## RESPONSE SHEET

```
METRIC-02  = Option ____     METRIC-13  = Option ____
METRIC-03  = Option ____     METRIC-14  = Option ____
METRIC-05  = Option ____     METRIC-16  = Option ____
METRIC-06a = Option ____     METRIC-17  = Option ____
METRIC-06b = Option ____     METRIC-19  = Option ____

METRIC-06b calculation + source definition:
    ______________________________________________________________

METRIC-18  producer — build an in-app render event?   Y / N ____

METRIC-12  resolved by evidence; answer only to overrule  = Option ____
METRIC-18  meaning ruled by direction K; answer only to change it = Option ____
```

**Ten fields need an answer. Two are there only if you disagree with the evidence.**

---

## METRIC-20 · Churn *(new — it was never on this sheet)*

**Design provenance.** `SCREEN-INVENTORY.md` and the Admin screens cited below live on the
design branch at commit **`931218b`** (`design/12circle-plus-admin-dashboard`), which is not an
ancestor of this branch — read them with `git show 931218b:<path>`.

**Why it is being added now.** `SCREEN-INVENTORY.md:33` names **churn** among the Control
Center's data requirements, and §196 established that the word appears **exactly once in the
entire approved design corpus** — that line — and **zero** times across all six screens, the
boundaries/components/provenance documents and the approved build spec. It was **absent from
this sheet entirely**, so it had never been put to the owner in either direction. The
approved monetisation roadmap names *"monthly churn"* under *Retention* without defining it,
and `COWORK` §8 forbids agents inventing monetisation.

**Question.** What is churn — which population, which window, and what event constitutes
leaving?

**Options as presented** (`V5_OWNER_DECISION_PACK_Q11_Q12.md`): `A` subscription churn,
state-based · `B` subscription churn, event-based · `C` coach-relationship churn ·
`D` activity churn · `E` defer and render `A11` empty.

**Evidence established.** The only cancellation timestamp in 180 migrations was
`coach_client_relationships.cancelled_at` (`025:19`); `subscriptions` had no end-date, no
status CHECK and no history table. On QA: 173 subscriptions all `active`, 0
`cancel_at_period_end`, and 175 relationships with 1 `cancelled` whose `cancelled_at` was
**null** — so no churn was observable in any form, and the single leave-event in the database
had no date.

**RESOLVED 2026-10-07 · METRIC-20 = Option B — subscription churn, event-based.**

> *"Define monthly subscription churn as: subscriptions canceled during the month ÷ active
> subscriptions at the beginning of the month."*

With: do not manufacture historical churn · do not infer cancellation dates from unrelated
fields · implement the minimum authoritative data contract to record **future** cancellation
events, including a cancellation timestamp and authorized writer path · preserve existing
data, no backfill · render the `A11` empty/insufficient-history state rather than a misleading
`0%` until sufficient real history exists · **no plan-level churn until `Q13`** · and `Q1`/`Q2`
ambiguity must not alter this subscription-based definition.

**Implemented** — migration `180` (§197). `subscriptions.canceled_at` added nullable with no
backfill; the authorized writer is the existing `stripe-webhook`
`customer.subscription.deleted` handler, which already writes `status = 'canceled'` and now
records Stripe's own `canceled_at` in the same update. The rate is **NULL** until any
cancellation has ever been recorded. **D20 · 23/23 live.**
