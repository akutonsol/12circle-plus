# 12 Circle Fitness — Master Product Decisions

**Wave 0 deliverable. Every unresolved decision extracted from workstreams A–N, deduplicated and owned.**
**Date:** 2026-08-24 · **Companion to** [`MASTER_REMEDIATION_REGISTRY.md`](MASTER_REMEDIATION_REGISTRY.md) and [`MASTER_REMEDIATION_WAVES.md`](MASTER_REMEDIATION_WAVES.md)

> **Nothing in this document is decided.** Where a recommendation is possible it is given
> and **labelled as a recommendation**. No clinical policy, business policy, monetization
> term, cancellation term, refund term, IAP choice, PAR-Q consequence or medical behaviour
> is chosen here.

> **Amendment, 2026-08-27 — additive, nothing above rewritten.** The sentence above was
> true as written at Wave 0 and is now qualified by one row: **`PD-A05` is `ANSWERED`**
> by the product owner on 2026-08-27 (option **(a)**). Every other row in this document
> remains undecided, and no clinical, business, monetization or PAR-Q policy has been
> chosen. The standing record of the answer and its rationale is
> [`decision-log.md`](decision-log.md), per §2 below.

> **Amendment, 2026-08-28 — additive, nothing above rewritten.** A second row is now
> qualified: **`PD-A23` is `ANSWERED`** by the product owner on 2026-08-28 (option
> **(b)** — drop the PostgREST embed, read coach profiles in a second query against
> `public_profiles`, no migration). It is an **engineering-owned** decision; the
> preceding amendment's statement that no clinical, business, monetization or PAR-Q
> policy has been chosen is **unchanged and still true**. Every row other than
> `PD-A05` and `PD-A23` remains undecided. Rationale recorded in
> [`decision-log.md`](decision-log.md), per §2 below.

---

## 0. How to read this

**73 canonical decisions**, reduced from 108 raw questions across the workstreams.
Grouped A–G by the authority required, not by the domain they affect.

| Field | Meaning |
|---|---|
| **Blocks** | Canonical finding IDs that cannot be built or closed without this answer |
| **Can engineering proceed?** | **Partly** means a mechanical half exists and is scheduled; only the policy half waits. This is the most important column — 31 of the 73 have a mechanical half that must not be held hostage to the decision |
| **Owner** | The authority required. `Julia` denotes product authority; `Clinical` denotes a qualified clinical owner, which the project does not currently name |
| **Wave** | Where the dependent work sits |

### 0.1 Decisions already closed — do not re-open

| Decision | Answer | Recorded |
|---|---|---|
| **Q-A — Does the deterministic engine prescribe?** | **YES. The deterministic coaching / program intelligence engine IS authoritative** for selection, order, sets, reps/ranges, rest, tempo, RPE/RIR, load, progression/regression, constraints, cues and warm-up. **AI is not an independent prescription authority.** Load rule: `weight_kg` nullable — `null` = no prescribed load, `0` = prescribed zero, a number = that load. **The engine must not invent a load merely because the field exists** | `WORKOUT_DOMAIN_CONTRACT.md` §8, product authority 2026-08-24 |
| **Q-B — What does "End Workout" mean?** | Pause / Discard / Complete, behind an honest two-choice dialog. Discarded sessions become `abandoned`, set logs preserved | Phase 2, implemented, live-verified |
| **Q-2 — Should `public.workouts` exist?** | Deferred, not decided — but **made inert and safe** (read-only catalog, migration 118) so retirement is no longer urgent. Re-filed below as **PD-A20** | Phase 1 §11 |

**Consequence of Q-A being closed:** `ENG-03` (the Coach Copilot UI writing `3×10@90s` for
every exercise) is no longer an open question about where prescription belongs. **It is a
contract violation** — the presentation layer is doing what migration 119 went to real
lengths to stop the engine doing. It is scheduled as a defect, not a decision.

### 0.2 Three questions that turn out to be already answered by governing documents

Recorded here because four workstreams filed them as open, and they are not. **Each is a
finding, not a decision.**

| Filed as open by | Question | The governing answer |
|---|---|---|
| C **A-2**, J **D-1**, `ENG-07`, `F-J-22` | Does the engine consume unreviewed knowledge? | **`product-bible.md` §6: AI may NOT "Recommend exercises outside certified knowledge."** `decision-log.md`: *"Knowledge is human-reviewed before the engine trusts it"* and *"the certification view is the single source of truth for 'can module X use this exercise?'"* → **The engine must gate on certification. `ENG-07` is a contract violation.** What genuinely remains is only the *predicate* — see **PD-A02**, narrowed accordingly |
| C **A-3**, J's B-1 | May an LLM-derived `intensity_delta` modulate training? | **`product-bible.md` §6: AI may NOT "Invent or alter programming, sets/reps, or progression."** → Routing a Claude-derived `intensity_delta` into the active-workout load cue and `generate_client_plan`'s structure **violates a stated hard constraint.** See **PD-A03**, which is now "how do we remove it", not "is it allowed" |
| `ENG-02`(c), `ENG-14` | Does the coach approval matrix matter? | **`product-bible.md` §6: AI may NOT "Bypass the coach approval matrix for coach-guided clients."** `decision-log.md` core invariant: *"Coaches approve consequential changes."* → An unwritten `weekly_feedback.subject_id` **silently disables the approval matrix**, which is a hard-constraint violation, not a feature gap. No decision needed; it is a P0 defect (AI-2) |

Likewise **`E-05`** (a client can retrieve the coach's private clinical `coach_text`)
violates the decision-log invariant *"AI communications are drafts a coach edits before
sending."* Scheduled as a defect.

### 0.3 What the approved roadmaps already settle — and one conflict they create

Two standing roadmaps are **APPROVED** and were not read against the code by any
workstream.

| Roadmap | Status | Effect on this programme |
|---|---|---|
| `ROADMAP_WEARABLE_INTELLIGENCE.md` | **APPROVED — FUTURE BUILD · implementation NOT AUTHORIZED.** Its own immediate action: *"Preserve roadmap; continue current QA/remediation program."* | **Out of scope.** It does not license any wearable work in Waves 1–9, and it is **not** an argument for keeping the integrations screen (**PD-B23**) — HealthKit is a different mechanism from the Strava/WHOOP/Garmin OAuth buttons |
| `ROADMAP_AI_MONETIZATION_UNIT_ECONOMICS.md` | **APPROVED FOR ROADMAP.** Mandates usage controls, an AI usage wallet, a cost ledger, model routing, caching, cost observability and abuse/cost protection | **Confirms rather than competes with Wave 6.** `K-03` (no server-side entitlement) and `P-11` (no spend cap across 12 AI functions) are not new inventions — the approved roadmap already requires exactly these controls. Cite it as the authority when building them |

> ### ⚠ **PD-E08 · The approved commercial architecture and the shipped tier ladder do not match**
>
> **This conflict is new to this reconciliation.** No workstream compared the roadmap to the code.
>
> | Approved roadmap §2 | Implemented in code (Workstream K) |
> |---|---|
> | **Free** — acquisition tier | *(no free tier is modelled in `client_plan()`'s ladder beyond the absence of a subscription)* |
> | **12Circle AI** — ~$19.99/mo or $149.99/yr | **`ai_guided` — $59/mo** |
> | **12Circle Coach** — ~$49–99/mo | **`coach` starter / growth / elite** (client→coach and coach→platform are separate products) |
> | *(no equivalent)* | **`self_guided` — $29/mo** |
> | **12Circle Fitness Operating Platform** — future B2B | not built |
>
> The roadmap states final pricing is *"intentionally open until real AI and infrastructure
> cost measurements are available"*, so this is not necessarily an error — but **the names,
> the count and the shape of the tiers differ, and five Stripe price ids, a capability
> matrix, `client_plan()`'s SQL ladder, the Dart `ClientPlan` enum and the paywall copy are
> all built to the implemented shape.** `K-15` already records "three-and-a-half tier
> representations, only one of which is synchronized"; **with the roadmap it is
> four-and-a-half.**
>
> **Decision required before Wave 6 stage 6.3 (`K-15`) and before any App Store product
> configuration:** is the implemented ladder the reality the roadmap will be revised to
> match, or is the roadmap the target the ladder must migrate to? **Owner:** Julia.
> **Recommendation:** freeze the implemented ladder for beta and treat the roadmap's tiers
> as the post-beta pricing experiment it describes (§13) — migrating a tier ladder while
> the webhook is not yet idempotent is the worst possible sequencing.

---

## A · Engineering decisions

*Decisions an engineering owner can take, but which are load-bearing enough to need a
recorded rationale rather than an implementer's choice.*

| ID | Decision | Blocks | Options | Recommendation | Proceed? | Owner | Wave |
|---|---|---|---|---|---|---|---|
| **PD-A01** | **The prescription rule.** Q-A settled that the engine prescribes; it did not settle *by what rule*. `build_workout` assigns no sets, reps, load, rest, RPE or tempo | `F-J-10`, `ENG-03`, contract gaps G-1/G-2/G-3 | (a) a new deterministic rule set producing sets/reps + %1RM or RPE; (b) engine prescribes **structure**, load derived from the member's own logged history by a progression rule; (c) coach programs carry load, engine programs show none | **(b), with (c) as the interim contract.** Deterministic, explainable, uses `workout_set_logs` which already exists, matches "progression" as an existing engine responsibility, and needs no new clinical model. **Note `product-bible.md` §7 forbids new foundational engines pre-beta — (a) is a new engine and is therefore post-beta** | **Partly** — the interim contract (`null` load, client renders "—", never "0 kg") already ships | Julia + coaching | 5 |
| **PD-A02** | **The certification predicate.** §0.2 establishes the engine *must* gate on certified knowledge. Open: which predicate | `ENG-07`, `F-J-22`, `F-J-23`, AI-4 | (a) `exercise_intelligence.status = 'approved'` only; (b) `exercise_certifications.<module>` true; (c) both; (d) drafts admitted with a recorded confidence caveat in the trace | **(b)** — the decision log already names the certification view "the single source of truth for 'can module X use this exercise?'", and every consumer was built to gate on it. **Warning: under (a) or (b), populating the QA substrate produces an engine that still selects nothing until a human reviews 22+ exercises. Budget the review, or Wave 5.2 stalls** | **No** — determines the join predicate and whether the substrate bootstrap is safe at all | Julia + clinical | 5 |
| **PD-A03** | **Removing the LLM from the training loop.** §0.2: routing a Claude-derived `intensity_delta` and `focus` into the load cue and program structure violates §6 | `ENG-03` adjacent, A-3 | (a) delete the routing; the daily insight becomes tone/emphasis only; (b) keep it as a *deterministic gate's input* — the engine reads it as a signal it may reject; (c) re-scope §6 | **(a)** — it is the only option that restores the invariant without amending it. If the signal has value, (b) is the migration path, but it needs a deterministic gate that does not exist | **Partly** — deletion is mechanical | Julia | 5 |
| **PD-A04** | **Rep ranges and RIR representation.** Q-A names "reps / rep ranges" and "RPE/RIR" as engine outputs; the product implements a single integer `reps` and `rpe` only. `"8-12"` is correctly refused today | contract gaps G-2/G-3 | (a) a range type in the canonical prescription + client rendering + logging semantic; (b) integer reps only, ranges deferred; (c) RIR as a distinct field vs a presentation of RPE | **(b) for beta.** This belongs to PD-A01's scope, not to a contract repair, and PD-A01 is post-beta under §7 | **Yes** — refusing `"8-12"` is correct today | Julia + coaching | post-beta |
| **PD-A05** | **Who may read a decision trace?** Migration 089 grants every `coach` read of **every** trace platform-wide. 12 Circle allows self-serve coach signup, so `coach` is not a trusted class. **Premise correction, 2026-08-27 (M-3):** an earlier revision of this row asserted that *"every sibling table chose 'active coach or admin'"*. That is **not** what the migrations say. Measured directly: `predictions` (095), `program_versions` (093) and `communications` (096) all use `role IN ('admin','content_manager')`; `intelligence_attribute_reviews` (091) and `decision_traces` itself (089) use `admin + content_manager + coach`. **No sibling uses `admin` alone.** The sibling *coach* arms are program-ownership or `coach_id` equality, not `is_active_coach_of`. The corrected premise does not change the defect — the unscoped `coach` arm — and the ruling below was taken with the correction in hand. **Sibling policies are separate decisions and are deliberately NOT changed by this ruling** | `F-J-12`, `E-04`, `E-16`, `ENG-22` | (a) subject + their active coach + admin; (b) (a) plus `content_manager` for engine QA; (c) status quo | **(a)** *(recommendation as written at Wave 0; retained unedited for the record)*. Adopt (b) only with a written, time-bounded reason, and never into production | ✅ **ANSWERED 2026-08-27 · option (a)** — product owner. Read scope is **subject + `created_by` + the subject's active coach + `admin`**; `content_manager` is **not** included. **M-1: the `created_by` arm is RETAINED** — a coach must keep read access to the audit record of a decision they themselves made, per `product-bible.md`'s principle that every recommendation is explainable from a recorded trace; the option text was silent on this arm and the silence is now resolved in favour of retention. **M-4: `F-J-12` is a SECURITY / AUTHORIZATION closure-class finding**, subject to `QA_CLOSURE_STANDARD.md` §2.1. **Not yet implemented:** applied migration 125 implements option (b); see registry §7.11 | Julia + privacy | 2 |
| **PD-A06** | **What must the engine do when it cannot plan?** `build_workout` cannot distinguish "no exercise fits" / "substrate empty" / "vocabulary mismatch" and reports all three as `200 {selected: []}` | AI-5 / `F-J-08`, `ENG-19` | (a) refuse (raise), as 119 already chose for `materialize_program_week`; (b) degrade to a template; (c) a typed "cannot plan" result with a reason code | **(c)**, with (a) as the fallback where a caller cannot handle a typed result. (b) is rejected: a template is an uncredited prescription | **No** | Julia | 5 |
| **PD-A07** | **Is an AI-generated workout a "prescription" for audit purposes?** — must it write a decision trace with a model id and an input snapshot? | `F-J-10`, `F-J-13`, `F-J-14`, `F-J-25` | (a) yes — full trace parity with engine decisions; (b) no — a suggestion, labelled as such and excluded from adherence | **(a).** The product bible's second principle is that *every* recommendation is explainable from a recorded trace. A prescription the member follows and cannot audit is the gap the whole architecture exists to close | **No** | Julia + compliance | 5 |
| **PD-A08** | **May a confidence score be shown when its inputs are known to have failed to load?** | `F-J-04`, `EC-02` | (a) suppress the score and say why; (b) show it with a degraded-input marker; (c) status quo | **(a).** Once `F-J-04` is fixed the number becomes meaningful; until then it is computed from silently-emptied arrays and is worse than absent | **Partly** — fixing the inputs is unconditional | Julia | 5 |
| **PD-A09** | **Which of the five duplicated `user_profiles` concepts is authoritative?** | `I-USR-03`, `I-INT-01`, `I-INT-02`, `I-NUT-02` | pick one per concept and retire the other | pick the column the **server** writes in each case; retire the client-written twin. Cleanly closes `I-INT-01`/`I-INT-02`'s root cause rather than just their symptom | **Partly** — the one-line column fixes land in Wave 3A regardless | engineering | 3A/7 |
| **PD-A10** | **Two parallel AI nutrition backends.** `ai_nutrition/` posts to the NestJS API (well-tested: controller, service, e2e, secret-hygiene specs); `ai_coach/` posts to the `ai-coach` Edge Function with `mode:'nutrition'` (untested). **Both ship in the client.** Until this is answered `API_BASE_URL` cannot be set meaningfully and QA tests whichever path it happens to open | `E-NUT-06`, EB-6, `ENV-8` | (a) NestJS canonical, delete the Edge path; (b) Edge canonical, delete the API; (c) keep both with a documented split | **(a)** — it is the only layer in the repository that already implements the full four-outcome error contract, and it is the only AI surface with tests. But it is **blocked on PD-A17** (the API runs nowhere) | **No** | Julia + engineering | 1/5 |
| **PD-A11** | **`ai-coach`'s `target_client_id`.** The client sends it on two coach-facing paths; the function destructures only `{message, mode}`, so **a coach asking to analyse a client receives an analysis of the coach.** Fails closed — but produces confidently wrong clinical-sounding output attributed to the wrong person | `F-J-18`, `F-J-19`, `E-11`, `E-CHK-07`, `EC-17` | (a) delete the parameter and the two coach-facing methods; (b) implement delegation behind `is_active_coach_of(target)` | **(a) for beta.** **(b) must not ship without the gate, or it becomes a P0** | **No** | Julia | 5 |
| **PD-A12** | **`enrich-exercise`.** Dead on arrival — it calls `seed_exercise` under the caller's JWT and 116 correctly revoked it. Every call spends a full Sonnet generation and then fails at the write | `E-03` | (a) retire in favour of `enrich-exercise-content`; (b) rewrite to write as service role | **(a).** `seed_exercise` writes the shared exercise library from caller-supplied `jsonb` and arguably should never be client-callable. **Do not simply re-allowlist it** | **No** | engineering | 5 |
| **PD-A13** | **`notify-coach-email`.** No authentication; the anon key satisfies the gate; `client_name` interpolated **raw** into a branded HTML template. **It has no caller in the codebase** | EDGE-1 | (a) delete; (b) service-role bearer + HTML escaping + rate limit, and find it a caller | **(a).** Deleting an orphaned mass-email endpoint that accepts attacker HTML is strictly better than hardening it | **No** — but deletion is minutes of work | Julia | 5 |
| **PD-A14** | **`send-checkin-reminder`.** No auth, no idempotency; N invocations produce N emails and N notifications per client | EDGE-2 | (a) service-role bearer check against a **non-empty** key + per-client-per-week idempotency key; (b) move the sweep into a `SECURITY DEFINER` SQL function invoked by cron, with **no HTTP surface at all** | **(b).** It removes the attack surface entirely rather than guarding it | **No** | Julia | 5 |
| **PD-A15** | **Redirect-URL allowlist.** `successUrl`/`cancelUrl`/`returnUrl` are taken from the request body and handed to Stripe — an open redirect with a trusted intermediary, with `{CHECKOUT_SESSION_ID}` appended to the attacker's URL | `E-07`, `K-21` | (a) allowlist of `APP_URL` origins; (b) accept caller-controlled redirects | **(a).** There is no product reason for (b) | **No** — but the answer is not in doubt | engineering | 6 |
| **PD-A16** | **`send-invite-email` authorization.** Any signed-in account — including a brand-new self-registered client — sends a branded 12 Circle invite to any address, with an unvalidated token and `reply_to` set to their own email | `E-15` | (a) require `role='coach'`, verify the token resolves to an invite owned by the caller, rate-limit per sender; (b) accept | **(a)** | **No** | Julia | 5 |
| **PD-A17** | **Where does the NestJS API run, and does the parallel auth stack stay?** No deployment target of any kind exists; `API_BASE_URL` is empty in every environment. A second auth stack (`firebase-admin`, `passport-jwt`, `bcryptjs`, `auth.controller`, `users.controller`) ships alongside the Supabase one | `ENV-8`, EB-6, `REL-29`, `REL-30`, `REL-28`, `LRE-14`, `LRE-22`, `LRE-23`, `LRE-38` | platform choice + keep/remove the dead stack | Platform is a cost and ops commitment and is genuinely open. **Removing the unused auth stack is not** — unused authentication is unmaintained attack surface. Recommend: decide the platform; **delete the parallel stack regardless** | **Partly** — the stack removal proceeds now | Julia | 1/8 |
| **PD-A18** | **Coach IP boundary.** `program_workouts` is now scoped to the program's parties. If coach programming is meant to be shareable (templates, marketplace programs) that needs an explicit sharing model | Phase 1 §10.4 | (a) programs stay private to their parties; (b) an explicit sharing/template model | **(a) for beta.** Widening the policy instead of building a sharing model would undo migration 117 | **Yes** | Julia | post-beta |
| **PD-A19** | **`admin` / `content_manager` assignment governance.** `admin_set_user_role()` exists and is logged, but there is no admin UI, no second-person approval, and "whoever holds `service_role`" creates the first admin on a fresh environment | Phase 1 §10.5 | (a) service-role-only bootstrap + a documented runbook; (b) an admin UI with second-person approval | **(a) for beta**, (b) before general availability | **Yes** | Julia | 8 |
| **PD-A20** | **Retire `public.workouts`?** 0 rows, no readers, now a read-only catalog. `workout_logs.workout_id` still carries an FK | `SEC-08`, `I-LEG-02` | (a) drop in a forward migration; (b) keep as an inert catalog | **(a)**, but it is a data-model decision because of the FK, and it is not urgent now that the surface is closed | **Yes** — it is inert and safe | Julia | 7 |
| **PD-A21** | **Set logs recorded against a swapped-out exercise.** They are completed history and must not be deleted. Open: do they remain visible in the session summary as work performed, or are they excluded from *program adherence* because the prescribed movement changed | Q-C | (a) retain, attribute to the exercise actually performed, count toward volume, exclude from "prescribed sets completed"; (b) exclude entirely | **(a)** — the client did that work | **Yes** — the current behaviour matches (a) | Julia | 4 |
| **PD-A22** | **Production's `dietary_restrictions` column type.** QA is `text`; the in-code comment asserts `text[]`, implying an out-of-band production change. **This is a fact-finding action requiring explicit authorization to read production** | `CON-03`, `Q-6`, `ENV-11` | (a) authorize a **read-only** production schema inspection; (b) write the forward migration to converge from either starting type without inspecting | **(b) now, (a) before rollout.** (b) is required regardless; (a) is a prerequisite for the production rollout plan, not for QA work | **Yes** — via (b) | Julia | 4 / 8 |
| **PD-A23** ✅ **`ANSWERED` 2026-08-28 · option (b) · owner: engineering** *(record: [`decision-log.md`](decision-log.md); registry §7.16)* | **The booking coach embed.** `/appointments` and `/book-call` use a PostgREST embed with no backing FK, so the query fails for every client | UIX-1 / `M-03` | (a) add the FK to `user_profiles`; (b) drop the embed and do a second query against `public_profiles` | **(b)** — no migration, and it matches the pattern `coach_relationship_service.dart` already uses | **Yes** — recommendation is unambiguous | engineering | 3A |
| **PD-A24** | **Observability vendor, cost, and data-residency posture.** No crash reporting, analytics, APM, structured logging, uptime monitoring or alerting exists in any tier | `EC-01`, `REL-26`, `LRE-27`, `LRE-28` | vendor choice | **Health and fitness data implies a privacy review of anything that leaves the device.** The sink abstraction (`reportFailure`) can and should be built **before** the vendor is chosen — it is one interface | **Partly** — the sink is unconditional and is Wave 3B-0 | Julia + privacy | 3B/8 |
| **PD-A25** | **What is beta?** A third Supabase project with its own data, or production data behind a flagged build? Testers today must run either a fixture-laden QA build or an **unpatched production** build. Neither is a beta | EB-11, `LRE-17` | (a) a third project; (b) production behind a flag; (c) QA promoted to beta with the seeds removed | **(a) or (c).** (b) is rejected while `ENV-11` stands — it points beta testers at the unpatched security surface. The choice is about who sees whose data | **No** | Julia | 8 |
| **PD-A26** | **Forward-only, or pay for PITR?** Zero down migrations across 123 files; free tier implies no PITR; the security rollout is a one-way door | `ENV-9`, `LRE-08` | (a) pay for PITR; (b) accept forward-only with rehearsed reverse scripts | Determines the acceptable blast radius of every production migration, starting with the security rollout. **Reverse scripts for 113–128, rehearsed on a QA clone, are required under either option** | **Partly** — write the reverse scripts now | Julia | 1/8 |

---

## B · Product decisions

| ID | Decision | Blocks | Recommendation | Proceed? | Owner | Wave |
|---|---|---|---|---|---|---|
| **PD-B01** | **Is there a daily check-in distinct from the weekly one?** `weekly_checkins` is real and populated; `checkins` has never existed; the product bible does not mention a daily check-in; every user-visible label already says "Weekly"; the "daily" methods have zero callers; `getCheckinStreak` computes a daily streak a weekly cadence can never satisfy | DAT-1, `E-CHK-01`, `E-CHK-02`, `I-CHK-01`, `I-LEG-03`, `M-02` | **Retire `CheckinService`; migrate every caller to `weekly_checkins`.** Low risk — the retired path has never successfully written a row, so no user data is affected. **This is a confirm, not an open question — but it changes user-visible behaviour, so it needs your word.** Note `/directory` currently labels the *daily* check-in "Weekly Check-ins" (`H-21`), which is evidence the duplication is accidental | **No** — this is the single largest blocked cluster | Julia | 4 |
| **PD-B02** | **Which `weekly_checkins` column family is canonical, and are `hunger_level` / `compliance_percent` part of the form?** The table carries two mutually exclusive families; the one writer uses the baseline set and four readers including two AI paths use the 001 set | `I-CHK-02`, `I-CHK-03`, `I-CHK-04`, `E-CHK-03`, `I-NUT-02` | The **001 family**, because four readers and both AI paths already use it and only one writer uses the other. **Must be answered with PD-B01 — repointing the writer without this still produces NULLs on every reader, and the AI prompt still receives the literal string `undefined`** | **No** | Julia | 4 |
| **PD-B03** | **Is body weight a check-in field or a `weight_logs` concern?** `weekly_checkins.weight_kg` exists and is read by four consumers but collected nowhere; `weight_logs` is written by `ProgressScreen` and read by neither the coach's check-in view nor `ai_adjust_nutrition` | `E-CHK-04`, `I-NUT-02`, any revival of nutrition auto-adjustment | Add weight to the check-in form — it is the natural weekly cadence and the coach review screen already expects it — **and** point `ai_adjust_nutrition` at `weight_logs` as a fallback. **One source must be declared canonical** | **No** | Julia | 4 |
| **PD-B04** | **Nutrition correction: audited correction row, or plain mutation?** Product bible §2.6 says completed history is immutable; nutrition logs are user-entered records rather than engine decisions, so a correction path is in scope | `E-NUT-02` | **Audited correction**, mirroring migration 111's `applyCorrection` pattern. A coach reviewing adherence needs to see that a 2 400 kcal day was edited down to 1 400 after the fact | **No** | Julia | 4 |
| **PD-B05** | **May the engine change a *coach-assigned* nutrition plan, or only a self-generated one?** `ai_adjust_nutrition()` currently overwrites in place, **under the coach's name**, destroying `notes` | `I-NUT-03` | Only self-generated. A coach's prescription is the coach's; an engine adjustment to it is a *proposal* requiring the approval matrix | **No** | Julia | 4 |
| **PD-B06** | **How far does nutrition move toward "the engine decides, AI explains" before beta?** Five AI paths across two backends, none deterministic, none writing a decision trace, two with no paywall | `E-NUT-06`, `E-NUT-11` | **Do the minimum now** — a `source`/`confidence` column so an LLM estimate is never silently indistinguishable from a measured value, and is excluded from the deterministic score until confirmed. **Schedule the deterministic planner post-beta** (`product-bible.md` §7 forbids new foundational engines pre-beta) and **stop describing generated plans as coaching output in the interim** | **Partly** — the minimum needs no decision | Julia | 4/5 |
| **PD-B07** | **Is water tracking in scope for beta?** Coaches can already set `water_target_oz` and the UI shows a water card, so the product currently *promises* the feature | `E-NUT-14` | **Wire it** — the coach-facing half already exists and a visible-but-inert control is worse than no control | **No** | Julia | 4 |
| **PD-B08** | **Are `/checkins` (an appointments calendar filed under check-in) and coach-side AI check-in analysis in scope for beta?** | `E-CHK-05`, `E-CHK-07` | Move `/checkins` out of the check-in feature and adjudicate it against `BookingScreen` separately; **delete `analyzeCheckins` until the coach-side AI story is designed** (its activation needs PD-A11's authorization change first) | **No** | Julia | 7 |
| **PD-B09** | **Should a client with no coach-assigned habits get a default starter habit set?** The app currently invents **eight habits with invented multi-day streaks and schedules device reminders for them** | `H-08` | **Removing the fabricated streaks needs no decision and must happen regardless.** Whether defaults exist at all does. If yes: which habits, seeded when, as **real rows with zero history** | **Partly** — the fabrication is deleted either way | Julia | 3C |
| **PD-B10** | **What is a challenge's progress, per `challenge_type`?** Which deterministic source advances `current_progress`, and when? `challenges` carries both `type` and `challenge_type`, and both `unit` and `target_unit` — the vocabulary itself is unreconciled | `H-09` | Reconcile the vocabulary first (engineering), then define progress per type. **The product bible forbids inventing a coaching rule, so this cannot be inferred** | **No** | Julia | 7 |
| **PD-B11** | **Which score is canonical — `score_events`/`user_scores` (server-authoritative) or `daily_scores` (client-written)?** Two systems, two disagreeing leaderboards, one of them client-writable | `H-11`, `H-15`, `R-01` | **`score_events`/`user_scores` canonical; `daily_scores` derived server-side.** Product bible §2.1 points hard at the former. Retiring `daily_scores` changes `/insights`, the Home Wellness Pulse and the coach leaderboard, so it is a real behaviour change | **No** | Julia | 2/7 |
| **PD-B12** | **Should a coach not accepting clients be hidden from the marketplace, or shown as unavailable?** | `H-12`, `SEC-12` | Shown as unavailable — hiding loses discovery. **The `is_demo` half needs no decision: filter it.** Migration 110 already states demo accounts are excluded from discovery and the RPC does not honour it | **Partly** — the demo filter lands regardless | Julia | 7 |
| **PD-B13** | **Should the hard-coded sample workout library exist at all?** Today it is indistinguishable from a real program, fully loggable, and Home starts one **credited to a fictional coach** when the member has no program | `H-14`, `H-18` | If a demo library is wanted it must be **visibly labelled and non-loggable**. Otherwise delete it and design the no-program empty state | **No** | Julia | 3C |
| **PD-B14** | **Which of the six notification preferences maps to which notification `type`?** The columns and the `type` vocabulary were never reconciled; the preferences are persisted and honoured by nothing | `H-10`, `I-NOT-06` | Reconcile the vocabulary, then enforce at the producer. **Enforcement belongs inside Wave 5's Edge Function work — the same `insert_notification()` and email producers** | **No** | Julia | 5/7 |
| **PD-B15** | **Retire or wire: `/pods` (Accountability Pods) and `/coach-client-workouts`.** Both are fully built with real tables, migration support and seeded QA data, and are **unreachable from anywhere in the UI** | `H-16`, M dec 7/8 | A roadmap call. If wired, Pods needs a Community tab or Directory entry. **Do not leave them half-shipped** — an unreachable route is a maintenance cost with zero product value | **No** | Julia | 7 |
| **PD-B16** | **What may a coach see about someone who has *requested* them but is not yet their client?** Name only? Name + goal? Name + email? Today the coach must accept requests from an anonymous "New Client" | `H-06` coach half, `R-05` | A privacy-policy call, not a technical one. `public_profiles` already supplies name/avatar/role; `fitness_goal` and `email` would need a new scoped path. **Decide alongside PD-B01/PD-B02 — both concern what a coach may see pre-relationship** | **Partly** — the **client half** of `H-06` (four client surfaces repointed at `public_profiles`) needs no decision and lands in Wave 3A | Julia + privacy | 3A/7 |
| **PD-B17** | **Is global exercise publishing moderated?** The migrations say yes (`050`); the app says no (`submitForGlobalLibrary()` writes `'approved'` itself). Separately, the admin tool that would approve is broken (`custom_exercises.approved_by` does not exist) | `I-COM-03`, `H-03`, `M-09` | **Moderated** — it is the same principle as the certification pipeline, and `product-bible.md` §6 forbids the engine consuming uncertified knowledge. The `approved_by` column fix can land now; the publish-path change must land with the moderation queue | **Partly** | Julia | 3A/7 |
| **PD-B18** | **May a sender edit or delete their own message after sending?** | `I-NOT-04`, `H-19` | **The security half is not a decision:** a participant must never be able to rewrite the *other* party's message, and that `WITH CHECK` lands in Wave 2 regardless. Only the sender's own edit window is a product call | **Partly** | Julia | 2/7 |
| **PD-B19** | **Is `workout_sessions` canonical, and must pre-`035` `workout_logs` history be preserved?** "A completed workout" is modelled twice and dual-written non-atomically, with disjoint readers | `I-LEG-01` | `workout_sessions` canonical. Preservation of pre-035 history is the real question — **six readers move together**, so this is one change, not six | **No** | Julia | 7 |
| **PD-B20** | **Are risk/progress insights a shipped feature? Do `exercise_analytics` and `score_cycles` have a consumer coming? Is "coach tips" a feature?** | `I-INT-03`, `I-LEG-02`, `I-LEG-03` | `coach_tips` has no product statement anywhere and has never existed as a table; the Home card shows a hardcoded string. **Recommend: delete the card and the read, or specify the feature.** The dead relations should be dropped or given a dated owner | **No** | Julia | 7 |
| **PD-B21** | **Is program deletion *archive* or *erase*?** | `I-USR-01`(a), `I-WRK-03` | Archive. **Critical ordering note: `I-WRK-03` (populating `workout_sessions.program_workout_id`) MUST NOT land before this is answered** — the FK is `NO ACTION`, so populating the column makes `generate_client_plan()`'s delete start failing with `23503` for any client who has trained | **No** | Julia | 4/7 |
| **PD-B22** | **What is the account-deletion contract the Help Center already promises?** 53 of 143 foreign keys restrict deletes, so deletion is blocked at the schema level | UIX-2, `REL-04`, `K-16`, `I-USR-01`(b) | Define: what is erased, what is anonymised, what is retained for financial/legal reasons, and over what window. **Independent of the decision, the false in-app claim must be corrected in Wave 1** | **Partly** — the text correction is unconditional | Julia + legal | 1/7 |
| **PD-B23** | **The integrations screen.** Strava, WHOOP, Garmin, Polar, Spotify and MyFitnessPal OAuth URLs are present; the screen **marks a service "connected" after launching a `YOUR_CLIENT_ID` URL.** Each provider requires an approved developer app and brand compliance | `M-05`, `REL-39` | **Hide unapproved providers for v1.** A connect button that cannot connect is a Guideline 2.3.1 exposure and a trust cost. **Note the wearable roadmap does not license this screen** — HealthKit is a different mechanism and is explicitly NOT AUTHORIZED | **Partly** — deleting the fake `_toggleConnect(id, true)` is unconditional | Julia | 3C/7 |
| **PD-B24** | **Navigation consolidation.** `AppShell._PersistentNav` and `AppScaffold`/`AppBottomNav` disagree on destinations; one is never rendered | M dec 9, `H-18` | Pick one. Pure cleanup, no user-visible change if done correctly | **Partly** | Julia | 7 |
| **PD-B25** | **Class JOIN / QR buttons — in v1 scope?** Currently no-op handlers | `M-12` | Remove the buttons or build the flow. **An inert button is worse than an absent one** | **No** | Julia | 7 |
| **PD-B26** | **`/checkin-detail` — build or unlink?** A live route rendering "Check-in details coming soon" | `E-CHK-06`, `H-20` | Unlink for beta | **No** | Julia | 7 |
| **PD-B27** | **Event tickets — standardise on the existing `qr_code`, or add `ticket_code`?** | DAT-4, `I-COM-01`, `I-COM-02` | **`qr_code`** — it exists, it is what the schema models, and the fix is three tokens. **The fabricating `catch` is deleted regardless of the answer** | **Partly** | engineering | 3A |

---

## C · Business decisions

| ID | Decision | Blocks | Recommendation | Proceed? | Owner |
|---|---|---|---|---|---|
| **PD-C01** | **Commission authority.** Is the marketplace rate global-only (today's *behaviour*) or per-coach negotiable (today's *stated intent*, and the column that exists)? And what exactly makes a client "coach-brought"? A coach can currently zero their own commission by pre-inviting the lead | `K-18`, `K-20`, `K-14` | Per-coach negotiable with a global floor, and a server-authoritative definition of "coach-brought" that the coach cannot set. Today's global-override defeats the per-coach column entirely | **No** | Julia |
| **PD-C02** | **Coach capacity — hard block or soft signal?** `max_clients` is granted, never revoked, and self-writable | `K-09` | Hard block, server-enforced. A soft signal that is also self-writable is not a signal | **No** | Julia |
| **PD-C03** | **Currency.** `'usd'` is hardcoded in every `price_data` and every table default. **Single-currency is a decision, not an oversight — but it should be a recorded one** | future i18n | Record it as a decision for beta | **Yes** | Julia |
| **PD-C04** | **What operational commitment is being made at launch?** An app holding cycle-tracking data, PAR-Q health history and payment relationships makes implicit promises in its privacy policy that the infrastructure does not currently keep | `REL-27`, `LRE-27`, `REL-26`, `REL-5` SLA | An accepted RPO/RTO, a named on-call owner for launch week, a support channel behind the Support URL, and a named owner for the 24-hour UGC takedown SLA. **This is a staffing commitment, not an engineering task** | **No** | Julia |
| **PD-C05** | **QA Anthropic spend cap, and may the batch enrichers run against the full library in QA at all?** 12 AI functions, no cost cap, no rate limit; the batch enrichers loop 20–25 serial Sonnet calls per request | `P-11`, `E-19`, BIL-2 | A QA-scoped key with a hard budget cap before Wave 5.0; batches at `limit ≤ 5`. **The approved monetization roadmap §5/§16 already mandates usage controls and abuse/cost protection — cite it as the authority** | **No** | Julia + finance |

---

## D · Clinical / safety decisions — **the highest-gravity group**

**No clinical policy is invented anywhere in this programme.** The project does not
currently name a clinical owner; **naming one is itself a prerequisite**, and it gates
five findings and the entire safety-wiring sub-wave (5.7).

| ID | Decision | Blocks | Current behaviour | Why it is not an engineering call | Proceed? |
|---|---|---|---|---|---|
| **PD-D01** | **What does each PAR-Q risk level and flag mean for programming?** Specifically: does `risk_level = 'high'` or `doctor_advised_no_exercise` gate AI programming behind clearance? Who may clear a member, and does clearance expire? What movement classes are contraindicated for `pregnancy` / `postpartum`, and by trimester or stage? | `CON-04`, AI-6/`F-J-05`, `ENG-12`, `F-J-09`, `F-J-13` | **Nothing consumes it.** `build_workout`'s context has no risk term; `score_exercise` has no PAR-Q dimension — passing `risk_level:'high'` changes no score by a single point. `client_detail_screen` displays it to the coach and that is all | This is medical policy. It must not be inferred from the model, from the code, or from an audit. The **mechanism** is clear and cheap — a risk term in the context plus a deterministic **rejection rule**, not a score penalty; the **policy** carries clinical weight | **Partly** — SEC-R2 (making the data recordable at all) and ERR-4 (rendering absent risk as "not assessed") are unconditional and land in Waves 2 and 3B |
| **PD-D02** | **Does the allergen guard block a generated plan, or annotate it?** | `E-NUT-05`, `CON-08`, `F-J-26` | **Allergies never reach the prompt at all.** The generator sends `Dietary restrictions: None` unless the user re-selects from six hard-coded chips | A deterministic post-scan produces false positives ("nut-free" contains "nut"; "coconut" is not a tree nut for most allergy purposes). Blocking is safer and more annoying; annotating is friendlier and shifts risk to the user. **A genuine safety-policy decision** | **Partly** — **loading the profile's declared allergies into the prompt is unconditional and does not wait on this answer.** Only block-vs-annotate does |
| **PD-D03** | **The fertile-window definition.** | `F-08`, `F-10`, `CON-10` | Cycle days 12–16 — five days, day 14 ± 2, i.e. **two days *after* the labelled ovulation day**. The conventional window is six days *ending* on ovulation day | Both the width and the placement are clinical parameters | **Partly** — `F-08` (render whatever window is chosen, instead of ignoring the computed one) and `F-10` (implement it consistently) are separable and land regardless |
| **PD-D04** | **May a *predicted* cycle phase be shown as the *current* one, and at what log age does it go stale?** | `F-09`, `F-13`, `CON-10` | **Unbounded.** A 400-day-old log renders as fact; a future-dated start silently becomes cycle day 1 | The **mechanism** is a defect and is fixable now; the **threshold** and the degraded presentation are product/clinical calls | **Partly** — carrying log age in `CycleStatus` and refusing to extrapolate from a future start need no answer |
| **PD-D05** | **Should fertility/conception information appear in a fitness product at all, and if so with what framing and disclaimer placement?** | `F-23`, `F-24` | "Fertile window now" shown inline; the disclaimer is below the fold and absent from every other surface | Fertility framing carries contraceptive-misuse risk **regardless of disclaimer wording.** Placement and prominence are a policy decision | **No** |
| **PD-D06** | **May cycle data be sent to a third-party LLM, and under what consent?** | `F-18`, `F-19` | Sent silently via the AI coaching Edge Function — no consent, no opt-out, `tracking_enabled` unhonoured, and the cycle row is passed in the `recovery` slot | A privacy and legal determination about a special category of health data | **Partly** — field projection, honouring `tracking_enabled`, and not mislabelling the row as `recovery` are ready either way |
| **PD-D07** | **Is a model's photo-derived calorie estimate allowed to be an input to coaching decisions, and must it be visibly labelled as an estimate to both the member and the coach?** | `F-J-27`, `E-NUT-13` | Indistinguishable from a measured value once logged | Accuracy expectations and disclosure are product/legal calls | **Partly** — the `source`/`confidence` column in PD-B06's minimum makes the distinction possible regardless |
| **PD-D08** | **Who is the clinical owner?** | PD-D01…PD-D07, Wave 5.7 | **Unnamed** | The programme cannot proceed past Wave 5.6 on any safety-policy item without one. **This is the first decision to take** | **No** |

---

## E · Monetization decisions

| ID | Decision | Blocks | Current behaviour | Recommendation | Proceed? |
|---|---|---|---|---|---|
| **PD-E01** | **Cancellation terms.** | `K-05` credit refund, `K-07`, UI copy | Immediate, no refund, remaining paid period forfeited — **and `cancel_at_period_end` also exists via the Billing Portal. The two paths coexist and disagree** | Not recommended here; it is a consumer-terms decision. **Note the disagreement is itself a defect regardless of which is chosen** | **No** |
| **PD-E02** | **Dunning grace window.** How long does a `past_due` member keep access? | `K-11`, `K-02` failure branch | **The first failed payment revokes access immediately** | A revenue-vs-churn trade-off. Industry norm is a grace period; immediate revocation on a transient card decline is unusually harsh | **No** |
| **PD-E03** | **Refund and chargeback policy.** What is revoked when a package is refunded after 3 of 10 sessions are used? Who absorbs the reversed Connect application fee? Is a dispute an immediate suspension? | `K-06` | **Refunds and chargebacks revoke nothing** | Marketplace terms | **No** |
| **PD-E04** | **Trials — offer one, and at what length?** | `K-29` | Resolvable but not creatable | Growth decision | **No** |
| **PD-E05** | **Proration on tier migration.** `update-subscription` uses `create_prorations`, so an AI→Self downgrade banks a credit against the next invoice rather than refunding | UI copy | Acceptable, but it is a pricing choice and **it is not stated anywhere in the UI** | **Partly** — stating it is unconditional |
| **PD-E06** | **Stacking.** May a client hold a platform membership **and** a coach subscription at once? | `K-08` | **Both are charged and `client_plan()` reports only the higher tier — so the customer pays twice and sees one plan** | Whatever the answer, the current state is a billing defect | **No** |
| **PD-E07** | **Is production billing live, or deliberately in Stripe test mode until launch?** The production slot holds a `pk_test_` key | `K-26`, `LRE-15`, `LRE-30`, `LRE-33` | Unknown | **Either real money has never moved, or the constant is wrong.** Determines whether existing subscription records are real, which determines the entire billing-migration plan | **No** |
| **PD-E08** | **⚠ The approved commercial architecture vs the shipped tier ladder** — see §0.3 | `K-15`, all App Store product configuration | Four-and-a-half unreconciled tier representations | **Freeze the implemented ladder for beta; treat the roadmap's tiers as the post-beta pricing experiment §13 describes.** Migrating a tier ladder while the webhook is not yet idempotent is the worst possible sequencing | **Partly** — reconciling the *implemented* representations proceeds now | Julia |

---

## F · App Store / platform decisions

| ID | Decision | Blocks | Recommendation | Proceed? |
|---|---|---|---|---|
| **PD-F01** | **How does the iOS app take money?** `self_guided` ($29) and `ai_guided` ($59) are digital services sold through hosted Stripe Checkout opened in an external browser. Guideline 3.1.1 requires IAP; 3.1.3(e) exempts person-to-person real-time services — a plausible argument for `coach`, very unlikely for the two digital tiers | REL-2 / `REL-05` / `D-K1`, Gate 4 | **(a) StoreKit 2 IAP for the digital tiers, Stripe retained for coach commerce and web.** It is the most work and the only option that does not amputate a revenue line. **It adds a second entitlement source of truth on top of a webhook that must already be idempotent — so it cannot start before BIL-1 and BIL-2 close.** (b) iOS ships coach-guided commerce only. (c) iOS ships free with no purchase surface — note Apple prohibits *linking or referring* to external purchase, so the app could not even mention it. **This report does not interpret App Store policy; it records the mechanism and the exposure** | **No** |
| **PD-F02** | **What is the launch platform, and what is the App Store's role in it?** The product is a working web application; iOS is greenfield | whether PD-F01 is on the critical path at all | **Web-first: launch the private beta on web where the product actually works, and treat iOS as the next milestone.** It removes PD-F01 from the beta critical path while leaving it fully in scope for launch. Consistent with `product-bible.md` §8 (the next milestone is the first private beta with real coaches) | **No** |
| **PD-F03** | **Is community/messaging in the v1 iOS scope?** Guideline 1.2 requires report, block, moderate, a published EULA and a documented 24-hour response commitment — **real engineering plus an operational commitment someone must staff** | REL-5 / `REL-16` | If PD-F02 is web-first, defer moderation to the iOS milestone and keep community web-only for the beta. **If iOS ships with community, moderation is non-negotiable and needs a named owner** (PD-C04) | **No** |
| **PD-F04** | **What is the product's canonical name, bundle identifier and marketing domain?** Four spellings ship today (`Circle Fitness`, `circle_fitness`, `12 Circle Fitness`, and the Android label is a raw package name on the user's home screen); iOS and Android bundle ids diverge; `12circle.app` is referenced as a redirect target and **cannot be confirmed registered or controlled** | `REL-11`, `REL-12`, REL-6/`REL-17`, `LRE-39` | **Decide before Stage 6 — the bundle identifier is immutable once the App ID is registered.** One display name, one bundle id, and confirmed domain ownership with DNS | **No** |

---

## G · Roadmap decisions

| ID | Decision | Status | Note |
|---|---|---|---|
| **PD-G01** | **Wearable Intelligence** — the ten-wave HealthKit → Apple Watch → adaptive-coaching programme | **APPROVED — FUTURE BUILD · implementation NOT AUTHORIZED** | Out of scope for Waves 1–9 by its own instruction (*"continue current QA/remediation program"*). Recorded so it is not accidentally started, and so PD-B23 is not mistakenly justified by it |
| **PD-G02** | **AI monetization & unit economics** — usage wallet, cost ledger, model routing, caching, cost observability | **APPROVED FOR ROADMAP**, standing alongside this programme | Its Wave 0/1 (economic baseline, AI cost instrumentation) **overlaps Wave 6** and should be co-owned. Its §5/§16 controls are the authority behind BIL-2 and PD-C05 |
| **PD-G03** | **12Circle Fitness Operating Platform (B2B)** | Future | No effect on this programme |
| **PD-G04** | **The premium UI transformation** | **Explicitly deferred behind this programme.** Per the brief: *do not make beautiful screens around broken contracts* | Begins after Gate 6. The direction (premium, 12Circle purple/black, strong typography, high-quality cards, excellent motion, clear hierarchy) is recorded and unchanged |
| **PD-G05** | **Specialist Training Agents** — a governed agentic coaching system in which the Personal Fitness AI Coach orchestrates specialist agents (strength, endurance, mobility, …) under shared member context | **Approved roadmap addition — Future Product / AI Architecture.** Added to `docs/` on 2026-08-24, after Wave 0 closed; preserved by W1-T1 | Its own *Current Priority* section defers to this programme explicitly: *"Roadmap only. Do not begin implementation until the current QA remediation program reaches the appropriate architecture/AI gate."* **Out of scope for Waves 1–9.** It does, however, constrain Wave 5 in one respect worth noting: its governance list (no specialist may bypass safety constraints, authorization, entitlement, the deterministic workout contract, exercise identity or auditability) is the same invariant set this programme is remediating — so the Wave 5 safety, provenance and entitlement work is a **prerequisite** for it, not a parallel track |

---

## 1. Decisions on the critical path

Answering these **eight** unblocks more work than the other 65 combined.

| Rank | Decision | Unblocks | Wave it stalls |
|---:|---|---|---|
| 1 | **PD-D08** — name a clinical owner | PD-D01…PD-D07, all safety wiring | 5.7 |
| 2 | **PD-B01 + PD-B02** — daily vs weekly check-in, and the canonical column family | 12 findings across five workstreams; the coach queue, compliance, the at-risk roster, Insights, the AI grounding packet, the 12 Circle Score and nutrition auto-adjustment all consume it | 4 |
| 3 | **PD-A02** — the certification predicate | AI-4, `ENG-07`, `F-J-22`, `F-J-23`, and **whether the substrate bootstrap is safe to run at all** | 5.2 |
| 4 | **PD-D01** — PAR-Q policy | The single largest safety gap in the product | 5.7 |
| 5 | **PD-A17 + PD-A10** — where the API runs, and which nutrition backend is canonical | The flagship AI surface in **every** environment | 1 / 5 |
| 6 | **PD-A26 + PD-A25** — PITR/forward-only, and what beta is | The entire production rollout chain, and Gate 5 | 8 |
| 7 | **PD-F02** — launch platform | Whether PD-F01 (weeks of IAP work) is on the critical path at all | 8 |
| 8 | **PD-E07 + PD-E08** — is production billing real, and which tier ladder is the target | The whole billing migration plan | 6 |

**Nothing in Waves 1, 2, 3A or 3B is blocked by any decision in this document.** That is
deliberate: the first three waves were sequenced so that the programme can run at full
speed while these answers are gathered.

---

## 2. Decision log discipline

When a decision is taken:

1. Record the answer and the **why**, including the trade-off, in
   [`decision-log.md`](decision-log.md) — that file is the standing record and already
   holds the core invariants this programme enforces.
2. Update this document's row to `ANSWERED` with the date and the owner.
3. Move every finding it blocked from `BLOCKED_DECISION` to `READY_TO_REMEDIATE` in
   [`MASTER_REMEDIATION_REGISTRY.md`](MASTER_REMEDIATION_REGISTRY.md).
4. Reflect the wave change in [`REMEDIATION_PROGRESS.md`](REMEDIATION_PROGRESS.md).
5. If the answer **reverses** an existing decision-log entry, mark the old row superseded
   rather than deleting it — the log's own instruction, and currently its
   *"Superseded / revised"* section is empty.
