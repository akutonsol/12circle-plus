# Delegated determinations — 2026-10-21

> **Provenance, stated first because it is the point of this document.** On 2026-10-21 the
> product owner (Julia) wrote, in chat: *"to be hone i am realying on you to determin 1,3,5,7"* —
> four items from a list Claude had put to her: **(1)** the weight field on the locked check-in
> screen, **(3)** the Home tip card, **(5)** `OD-QAX-2` and `OD-14`, **(7)** the seven orphan
> routes. **Every determination below is Claude's, made under that delegation.** None is the
> owner's own wording. Under `V5_OWNER_AUTHORITY_DIRECTION_2026-10-21.md` a conversational
> direction is intent, not authorization; these are recorded through the standing record
> (`decision-log.md`, per `MASTER_PRODUCT_DECISIONS.md` §2) with that attribution, and the owner
> may overturn any of them. **Nothing here applies a migration, touches QA or production, or is
> `implementation_authorized` in `.skills-agent/decisions.json`** — that last step is a separate
> act, and for the two security items it is deliberately left to the owner (§4).

## 1 · Weight on the weekly check-in — `PD-B03`, form half

**Question.** `PD-B03` was confirmed in principle ("add weight to the check-in form"), but
`/daily-checkin` is **`FIT-004`, owner-locked**, and the locked frame draws no weight field.
Two owner-originated sources disagree.

**Determination: do not add the field. Body weight has one canonical source — `weight_logs`.**

- The existing weigh-in (`progress_screen.dart`, `LogWeightSheet`; kg canonical, kg/lbs toggle,
  factor `2.20462`) is the place weight is entered. It already writes `weight_logs`.
- `weekly_checkins.weight_kg` stays a declared, nullable, **unwritten** column. Nothing is
  dropped; no data is lost.
- The locked frame is **not** altered, which is the reading that honours both sources: the owner
  confirmed that weight must have *one declared canonical source* (her words, via the
  recommendation she confirmed), and she locked a frame that does not draw the field.
- **Consequence for the readers.** The consumers of `weekly_checkins.weight_kg`
  (`insights_provider.dart:108`, the coach review views, `ai_adjust_nutrition`) currently get
  NULL. They should read `weight_logs` (latest entry in the check-in's week) and treat
  `weekly_checkins.weight_kg` only as a legacy fallback. That is **follow-up work, not done
  here**: the Dart readers are queue work, and the `ai_adjust_nutrition` change is SQL, so it
  needs a migration whose number is taken at wave entry (`V5-PROD-011`), written but never
  applied without an owner-approved QA window.
- **What would change this:** the owner asking for the field. Then the frame is re-locked first.

## 2 · The Home coach card — `PD-B20` (coach-tips part only), `I-LEG-03`

**Question.** `coach_tips` has never existed. `_CoachTipCard` on the locked Home frame
(`FIT-001`) fell back to a hard-coded sentence shown under the assigned coach's **name and
avatar** with a **TIP** badge — a message attributed to a coach who never wrote it.

**Determination: coach tips are not a shipped feature; retire the fabricated tip and its read.**

- Done in code: the tip text, the TIP badge and `coachTipProvider` are removed; the
  `coach_tips` entry leaves the contract allowlist, which is now **empty**.
- **Kept deliberately:** the card itself — the coach's name, avatar and the **Rate** button. Rate
  is a real, working feature and this card is the only place in the app that opens it
  (`_showRateCoachDialog` has no other caller); removing the whole card
  would have deleted it. The card is shorter, not gone.
- A tip may return, but only with a backing table, an authoring surface for the coach, and an
  owner statement of the feature. `home_coach_card_honesty_test.dart` fails if a hard-coded tip
  returns under the coach's name; it is meant to be *rewritten* then, not deleted.
- **Not decided here:** the rest of `PD-B20` (risk/progress insights, `exercise_analytics`,
  `score_cycles`). Only `I-LEG-03`'s coach-tips part is determined.
- **Open flag for the owner:** if the locked `FIT-001` frame draws tip text in this card, the
  shipped card now differs from it. The frame was never reconciled to a tip that could not exist.

## 3 · The seven orphan routes

**Principle applied.** A route with no entry point is only a defect if something *should* lead to
it. The repository's own guard (`route_preservation_guard_test`) treats a silently vanished
route as the worse failure, and three of these are load-bearing in ways the orphan guard does
not show (`app_shell.dart:74` special-cases `/log-meal`; `qa_suites.dart:237-239` gates three of
them in the live QA run; `checkin_form_screen.dart` cites the stub pattern). So: **wire what is
a real, finished feature; leave stubs and aliases exactly as they are and say why.**

| Route | Determination | Reason |
|---|---|---|
| `/pods` | **Wired** — an *Accountability Pods* card at the top of Community → Groups | A finished, non-locked screen (FIT-071..074) with real tables (`accountability_pods`, `accountability_pod_members`) and an admin metric (`METRIC-13`) that counts pods; nothing led to it. Done; the guard's allowlist loses the entry. |
| `/log-meal` | **Keep as is** | A redirect stub to `/meals-dashboard`, the sanctioned resolution of locked FIT-019; the shell and the QA suite both depend on it. |
| `/food-search` | **Keep as is** | The same redirect stub; gated in the QA suite. |
| `/nutrition-overview` | **Keep as is** | `NutritionScreen` is embedded in `home_org.dart`; the route is gated in the QA suite. Retiring it removes coverage for no gain. |
| `/coach` | **Keep as is** | A duplicate alias of `/train`. Harmless, and a stored deep link or notification payload could still name it — which cannot be ruled out from the repository. |
| `/coach-business` | **Keep as is** | Reachable from three screens by direct push; the named route is redundant, not dead. Migrating those callers is cosmetic and changes navigation semantics. |
| `/onboarding` | **Preserve — not a ruling** | Locked `FIT-006` Welcome vs. a different shipped intake flow (`OD-31`): two owner-originated sources disagree. The owner-authority rule is *preserve, identify, ask*; wiring or retiring it would choose a first-run experience, so it is left exactly as is and **returned to the owner**. |

Net effect: the orphan allowlist drops from 7 to 6, and the only one that needs the owner is
`/onboarding`.

## 4 · `OD-QAX-2` and `OD-14` — the two security policies

**These are P0 / F-21 authorization policies.** The determinations below fill every sub-question
the packet said must be answered before a migration can be shaped. They are written so that a
reviewer can reject any line without unpicking the rest. **They are recorded as determined; they
are not marked `implementation_authorized`**, because that is the one gate whose purpose is to put
a human's eyes on a security policy before code is written (§5).

### 4.1 `OD-QAX-2` — may a coach assign plans/programs to a `pending` client? **No (Option A).**

| Sub-question | Determination |
|---|---|
| Headline | **Option A.** Only a coach with an **`active`** `coach_client_relationships` row for that client may assign. |
| `Q-A1` direction / identity | The caller is `auth.uid()`, and must be the **coach** side of an active relationship naming `p_client_id` — the predicate `is_active_coach_of(p_client_id)` (migration 100). `coach_id` stays taken from `auth.uid()` inside the function. No role-based bypass is added by this change. |
| `Q-A2` status domain | `active` authorizes. `pending`, `cancelled`, ended, and no-row do **not**. This follows migration 113's consent model (*never grant a write path that lets one party name the other without consent*). |
| `Q-A3` error semantics | `42501 insufficient_privilege`, **one message for every refusal reason**, so the function is not an oracle for whether a relationship exists. |
| `Q-A4` the direct RLS path | **In scope as an audit, not a rewrite.** Verify the table policy already refuses what the function now refuses; change it only if it permits what the function must not. The function and the policy must agree. |
| `Q-A5` fixtures | Unrelated caller refused with the victim's active plan unchanged; coach-created `pending` row does **not** authorize; `cancelled` does not; **an active coach still assigns (positive control)**; `search_path`, grants and `COMMENT` preserved per the Function Replacement Rule (`CREATE OR REPLACE` keeps ACL and owner, not `proconfig` or body). |

**Product consequence, stated plainly.** A coach can no longer pre-assign a nutrition plan to a
client who has been invited but has not accepted. The plan is assigned after acceptance. That is
the weaker-for-coaches and stronger-for-members direction, chosen deliberately.
**Verified in this repo:** the only Dart caller is `client_detail_screen.dart:1824` (the coach's
client-detail view). **Not verified:** whether that view can be opened for a `pending` invitee —
if it can, a coach there will now get a refusal and the screen should say so plainly.

### 4.2 `OD-14` — who may create a programme, and what happens to existing rows?

**Framing answered:** *programme creation / policy population* (the ledger's framing, per
`F21_BLAST_RADIUS.md §6`), **not** team semantics (`D1`, already answered 2026-09-27).

| Sub-question | Determination |
|---|---|
| Is `is_coach_profile()` sufficient? | **No for any write that names a client; yes for a coach's own unassigned template.** Creating or assigning anything *to or about a specific client* requires an **active** relationship (`is_active_coach_of`). A programme template that names no client needs only `is_coach_profile()`. |
| `B-09` (1): does it bind creation or only assignment? | It binds **every client-naming write** — creation of a client-targeted row as well as assignment. Template authoring is out. |
| `B-09` (2): is `coach_video_responses` in scope? | **Yes** — it names a client. |
| `B-04`: registry (`Owner? = no`) vs ledger (`OD-14.blocks`) for `QAX-SEC-03` | **Build to the stricter contract.** `QAX-SEC-03`'s six tables (`client_habits`, `action_items`, `coaching_calls`, `coach_video_responses`, `client_nutrition_plans`, `workout_program_assignments`) are implemented under this decision. That satisfies **both** readings, so the dispute does not have to be settled to proceed. The registry's `Owner?` cell is **not** edited here (protected, and unnecessary for this). |
| `B-10`: existing non-conforming rows | **Preserved, not mutated, not hidden from the person they are about.** A row that would not be writable under the new policy stays readable to the client it names and to its original coach as today; it simply cannot be *changed or re-created* by a coach without an active relationship. They are listed for review rather than deleted or rewritten. |
| `Q-B5`: who reviews | The **platform `admin` role** (capability-gated through `admin_can`), initially the product owner. **This is the one fact Claude cannot verify** — who holds that role in production — and it is flagged for the owner. |
| First step of the migration | A **read-only count** of non-conforming rows, run only in an owner-approved QA window. If the count is zero the review list is empty and the quarantine arm is moot. |

Per-table regression criteria are the packet's: a coach with no active relationship cannot insert
or update a row naming a victim; an active coach can; existing victim rows cannot be blanked or
hijacked; notification side effects do not fire for an unauthorized write.

## 5 · What this does not do, and the one step left to the owner

- **No migration is written, numbered or applied.** Numbers are taken at wave entry.
- **Nothing is applied to QA or production.** Migrations 182 and 183 stay unapplied.
- **`.skills-agent/decisions.json`** moves `OD-QAX-2` and `OD-14` to `recorded`, naming this
  document and the delegation. It does **not** set `implementation_authorized`. The state chain
  says each step is *a separate act*, and `accepted` means *"the owner accepted it, verbatim"* —
  which a delegation is not.
- **The step that remains is one sentence from the owner**, after reading §4: *"authorize
  implementation of OD-QAX-2 / OD-14"* (or *"change X"*). Until then the two tasks stay gated, which
  is the gate working as designed rather than an obstacle.
- `I-CHK-01`, `I-CHK-03`, `QAX-SEC-01` and `QAX-SEC-03` remain open: none reaches *VERIFIED
  END-TO-END* without a live QA read.
