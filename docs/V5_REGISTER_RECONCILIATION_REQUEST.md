# V5 · REGISTER RECONCILIATION REQUEST — one stale clause in `PD-A05`

**This document changes nothing.** `MASTER_PRODUCT_DECISIONS.md` is under a standing
do-not-modify constraint, so the finding below is reported for **owner-authorized**
reconciliation rather than corrected. The register is unmodified: 281 lines, last touched by
`527438a`, which is not this programme's work.

---

## The clause

`docs/MASTER_PRODUCT_DECISIONS.md:119`, at the end of row **`PD-A05`**:

> **Not yet implemented:** applied migration 125 implements option (b); see registry §7.11

## Why it is stale

It was true when written and has since been superseded. The owner answered `PD-A05` as
**option (a)**; migration **125** implemented option (b); migration **128** then implemented
option (a) and is the policy in force.

| evidence | what it establishes |
|---|---|
| `supabase/migrations/128_scope_decision_trace_reads_option_a.sql` | Creates `"dtrace read own/creator/active-coach/admin"` — `subject_id` OR `created_by` OR `is_active_coach_of(subject_id)` OR `public.is_admin()`. `content_manager` is not granted. Its header states it enforces *"PD-A05 **option (a)**, as ruled by the product owner on 2026-08-27"*. |
| `MASTER_REMEDIATION_REGISTRY.md` row `F-J-12` | ✅ **`VERIFIED_CLOSED` 2026-08-27** (CI run **#32** at `ae5be13`), **all four** SECURITY/AUTHORIZATION states present — FIXED IN CODE · FIXED ON QA · VERIFIED LIVE · VERIFIED IN CI. Decision column reads ✅ **PD-A05 (a)**. |
| the same row, live evidence | `content_manager` reads **0** rows where the identical probe read **90** pre-128; unrelated coach 0; unrelated client 0; subject 95/95 of their own. |
| `MASTER_REMEDIATION_REGISTRY.md` (§7.11 narrative) | *"when §0.2's 125 assignment was spent and **option (a) landed at 128**"*. |
| `SEC-G11` (new, this programme) | 14 assertions pinning 128's shape arm by arm, including that `content_manager` is not granted and that no bare role-class arm exists. Negative-controlled on two vectors. |

**125 was not edited, and should not be.** Its own successor says why: *"an in-place edit of an
applied migration is ENV-2 / CRC-13 — the defect this programme is remediating."* 128 is the
forward correction. So the implementation history is correct; only the register's closing clause
describes a state that no longer exists.

## Why this is worth your attention rather than a footnote

**The clause reads as unbuilt authorized work.** I found it while sweeping for exactly that —
decisions the owner has answered that nobody has implemented — and it was the only hit. Acting on
it would have meant **re-implementing a `VERIFIED_CLOSED` P1 security finding**, which is both
wasted work and a live risk: a "re-implementation" of a policy that is already correct is an
opportunity to get it wrong.

The investigation is what established it was stale. That is the argument for reconciling the
clause rather than leaving it: the next reader has to repeat the same investigation to reach the
same conclusion, and may not.

## What is requested

Authorization to replace the single clause

> **Not yet implemented:** applied migration 125 implements option (b); see registry §7.11

with a statement of the current state, for example

> **IMPLEMENTED:** migration **125** implemented option (b); migration **128**
> (`128_scope_decision_trace_reads_option_a.sql`) implements the ruled **option (a)** and is in
> force. `F-J-12` is `VERIFIED_CLOSED` (CI run #32, `ae5be13`) with all four
> SECURITY/AUTHORIZATION states present. Pinned by `SEC-G11`. See registry §7.11.

**Scope of the request, deliberately narrow.** One clause in one row. **No** change to the
ruling, the option text, the recommendation, the premise correction, `M-1`, `M-3`, `M-4`, the
dependency column, the owner column, or any other row. **No** change to the 73-decision count.
Nothing else in the register is proposed for edit, and no other register is touched.

**Not requested:** any change to migrations 125 or 128, to `F-J-12`'s closure state, or to the
`MASTER_REMEDIATION_REGISTRY` row — which is already correct.

## A second, separate note — not part of this request

The same `F-J-12` row carries a **retained limitation** that was **not** stale:

> *"RLS policies are outside the I-MIG-03 durability guard, which tracks function properties
> only — this closure has **no standing guard** against silent replacement."*

`SEC-G11` now supplies that guard at the **test** level, wired into CI with a two-vector negative
control. It does **not** close the limitation as written, because the limitation is about the
**I-MIG-03 durability guard / Gate 0.14**, and both migration 128 and registry §7.11 record
whether that gate should cover policies as an **open governance question**. That question is
untouched and remains open.

Whether the registry's limitation (i) should now be annotated to reference `SEC-G11` is a
separate authorization, on a separate register, and is **not** requested here.
