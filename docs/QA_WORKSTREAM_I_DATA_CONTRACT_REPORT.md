# 12 Circle Fitness — QA Workstream I
## Database & Data-Contract Audit

**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environments:** QA `eyqtldjqpgpljlqvpowh` — read-only introspection + two read-only REST probes.
**Production `nxdbooufqzkpslkcogxc` was not contacted. See §14.**

**Scope:** consistency between migrations, the live schema, functions/RPCs, triggers,
constraints, indexes, application writers, application readers, Edge Functions, the
NestJS API, and tests. This is **not** a second Phase 1 security audit; RLS/EXECUTE/
`search_path` appear only where a data-contract dependency required verification, and
that verification is reported in §3.4 as *confirmation*, not as new findings.

**Companions:** [`MASTER_QA_RECONCILIATION.md`](MASTER_QA_RECONCILIATION.md) ·
[`QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md`](QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md) ·
[`QA_WORKSTREAM_E_NUTRITION_CHECKIN_RECONCILIATION.md`](QA_WORKSTREAM_E_NUTRITION_CHECKIN_RECONCILIATION.md) ·
[`QA_WORKSTREAM_F_WOMENS_HEALTH_REPORT.md`](QA_WORKSTREAM_F_WOMENS_HEALTH_REPORT.md) ·
[`WORKOUT_DOMAIN_CONTRACT.md`](WORKOUT_DOMAIN_CONTRACT.md)

---

## 1. Executive summary

**The schema itself is in excellent condition. What is broken is the contract between it
and the code that reads and writes it.**

Three structural results, each verified live this session, frame everything below.

**First: migrations and the live schema agree exactly.** Replaying all 123 files in
`supabase/migrations` reproduces the live QA `public` schema **byte-for-byte at table and
column level — 91 tables, zero column drift** (§3.2). There is no schema
drift to find. Phase 1's security work is also confirmed landed: 91/91 tables have RLS
enabled with at least one policy, **zero** functions are executable by `anon`, all 47
client-called RPCs are granted to `authenticated`, and **131/131** functions carry a
pinned `search_path` (§3.4).

**Second: the application names things the database does not have, and the failure is
always silent.** Two relations and nine columns named by the client and the Edge
Functions do not exist. PostgREST rejects an unknown column with **HTTP 400 / `42703`
*before* it evaluates authorization** — confirmed live against QA — and every one of
those call sites wraps the request in a `catch` that returns `[]`, `false` or `null`.
The result is not an error a user or a test can see; it is a feature that ships dead.
This single mechanism accounts for: the entire check-in feature, the AI coach's user
profile, the AI workout generator's **injury and contraindication input**, meal
suggestions, exercise progression charts, event ticketing, admin exercise moderation,
and chat image messages.

**Third: several server-side behaviours are unreachable because their precondition is
written by nobody.** The coach check-in notification trigger returns early unless
`weekly_checkins.coach_id` is set — and no writer in the tree sets it, so the trigger has
never fired; the Dart-side notification was deliberately deleted in reliance on it.
`ai_adjust_nutrition()` needs two `weekly_checkins.weight_kg` values, which no writer
produces, and would raise `42703` on a nonexistent `user_profiles.goal` if it ever got
past that guard. `workout_sessions.program_workout_id` has no writer at all, so no
session can be attributed to the program day it came from.

**The most serious single finding is I-INT-02.** `ai-generate-workout` selects
`user_profiles.goal, equipment` — neither column exists — so the whole query 400s and the
generator loses `has_injuries`, `injury_locations`, `experience_level` and
`training_location` **in the same failed request**. The workout generator is producing
prescriptions with no knowledge of the user's injuries. That is a safety property, not a
feature gap.

**The most serious systemic finding is I-CHK-04.** The QA fixtures write the *opposite*
`weekly_checkins` column family from the one the application writes, and leave `status` at
its `'pending'` default. QA therefore looks populated to the coach dashboard and the
Insights panel while the real write path produces rows those surfaces cannot read — and
the coach review queue, which filters `status = 'submitted'`, is empty even with seeded
data. **The fixtures mask the defect they were meant to exercise.**

| Severity | Count | Meaning |
|---|---|---|
| **P0** | 5 | Data is lost, fabricated, or a safety input is silently dropped |
| **P1** | 17 | A domain is structurally non-functional, or integrity can be corrupted |
| **P2** | 16 | Real defect with a bounded blast radius, or a latent hazard |
| **P3** | 5 | Hygiene, dead weight, vocabulary drift |
| **Total** | **43** | Plus one verified-correct result recorded as I-PAY-03 |

**Newly built and green:** a schema-contract guard (`npm run test:contract`) that derives
the schema offline from the migrations and fails on any relation or column the
application names but the database does not have. It is the regression net for eight of
these findings and it has teeth — proven by injection (§11.3).

---

## 2. Method and evidence classes

| Mark | Meaning |
|---|---|
| **LIVE** | Reproduced against QA this session with a read-only operation |
| **DERIVED** | Proven mechanically from the live schema dump + source, by a script in §11.4 |
| **SRC** | Proven by reading the working tree |
| **CITE** | Previously recorded by another workstream; **re-verified current** here |

Steps actually performed:

1. `supabase db dump --linked --schema public` → 10,352 lines of authoritative DDL for QA.
   Every schema claim below is quoted from that dump, not from a migration file.
2. `supabase migration list --linked` → applied-vs-local migration history (§7.1).
3. A migration replayer (`supabase/tests/contract/schema.mjs`) that reconstructs
   tables/columns from `supabase/migrations`, diffed against the live dump (§3.2).
4. Mechanical cross-checks of every `.from()`, `.select()`, `.insert/.update/.upsert()`
   and `.rpc()` in `apps/mobile/lib`, `apps/api/src` and `supabase/functions`
   against the live schema (§11.4).
5. Two read-only REST probes with the QA **anon** key to establish PostgREST's
   error ordering (§11.2). No write probe was issued. See §13.
6. Full source reads of every trigger function, every RPC quoted, and every call site
   named in a finding.

**Prior reports were treated as historical evidence.** Each inherited finding was
re-derived against the *live* schema before being called open; §4 marks these `CITE` and
states what is new. Nothing is asserted on the authority of a previous summary. Prior
workstreams B, E and F recorded that they contacted no environment; the live confirmation
of their source-level conclusions is this report's contribution to them.

---

## 3. Schema census, parity, and what is already correct

### 3.1 Census (live QA, `public`)

| Object | Count |
|---|---|
| Tables | 91 |
| Views | 5 (`coach_client_workout_stats`, `conversation_participant_profiles`, `exercise_certifications`, `exercises`, `public_profiles`) |
| Functions | 131 (108 `SECURITY DEFINER`) |
| Triggers | 31 |
| RLS policies | 166 |
| Foreign keys | 143 |
| UNIQUE constraints | 27 (+ 4 unique indexes) |
| Indexes | 78 |
| CHECK constraints | 11 inline + 2 added by `ALTER` (**both `NOT VALID`**) |

### 3.2 Migrations vs current schema — **exact parity** · DERIVED

Replaying `CREATE TABLE` / `ALTER TABLE ADD|DROP|RENAME COLUMN` across all 123 migration
files in filename order yields **91 tables** whose column sets are **identical** to the
live dump. Zero tables in migrations but not live; zero live but not in migrations; zero
columns either way.

This is a strong result and it is worth stating plainly: **`supabase db reset --linked`
is a trustworthy way to rebuild QA**, and the offline schema model the new contract guard
depends on is sound. It is also what makes every "column does not exist" finding below
unambiguous — the column is absent from the migrations *and* from the live database.

Caveat recorded honestly: parity was measured between the **working tree** (which
contains 15 modified historical migrations and 20 untracked ones) and live QA. QA was
rebuilt from exactly those files. See §12.

### 3.3 Migrations 113–121 — downstream verification · LIVE

Every object those migrations create is present live: `is_coach_profile`, `may_notify`,
`is_canonical_exercise_prescription`, `plan_day_titles`, `resolve_exercise_media_for`,
`can_act_for`, `can_read_program`, `enforce_checkin_authorship`,
`enforce_profile_privilege`, `derive_parq_risk`; the `relationship parties *` /
`owner or active coach *` / `intel read staff only` / `notify a known counterparty`
policies; the `workout_set_logs_session_exercise_idx` and `workout_set_logs_instance_idx`
indexes; the `program_workouts_exercises_canonical` and `workout_sessions_status_known`
constraints; and all seven triggers from 115/119/120.

They are **applied but not recorded** in the remote migration history — see **I-MIG-01**.

### 3.4 Phase 1 posture — confirmed closed on QA · LIVE

Verified because later findings depend on these being true, not to re-audit them:

| Property | Result |
|---|---|
| Tables with RLS disabled | **0 / 91** |
| Tables with RLS but no policy | **0 / 91** |
| Functions granted `EXECUTE` to `anon` | **0 / 131** |
| Client-called RPCs not granted to `authenticated` | **0 / 47** |
| Functions without a pinned `search_path` | **0 / 131** |

The memory note "the 3× P0 are fixed on QA by migrations 113–118; prod still unpatched"
is **confirmed for QA**. Production was not contacted and is not characterised here.

### 3.5 RPC contracts — no defects found · DERIVED

All 47 client `.rpc()` call sites were matched against the live signatures:

* **Parameter contracts (item 11):** zero mismatches. Every named parameter exists on the
  target function and every non-defaulted parameter is supplied.
* **Return contracts (item 12):** zero defects. Every call site type-guards its result
  (`if (res is Map) … if (res is List) …`), so the `TABLE`-returns-an-array vs
  `jsonb`-returns-a-value distinction is handled correctly everywhere, including the
  three sites that accept either shape (`certification_summary`, `exercise_content_stats`).

This is the healthiest layer in the system and is reported as such.

### 3.6 Trigger ordering — correct, but implicitly · SRC

`user_profiles` carries two `BEFORE INSERT OR UPDATE` row triggers. Postgres fires them in
**name order**, so `trg_profile_parq_risk` runs before `trg_profile_privilege`. That
ordering is correct: parq derives `risk_score`/`risk_level`/`risk_flags`, and the
privilege trigger does not guard those columns, so nothing is clobbered and nothing is
rejected. The ordering is *load-bearing but undocumented* — it depends on the alphabet.
Noted, not filed as a finding, because the current pair is order-insensitive in fact.

---

## 4. Domain-by-domain findings

Every finding carries: severity · schema object · writers · readers · expected contract ·
actual contract · evidence · root cause · integrity impact · responsible migration ·
recommended fix · product decision · parallelizable.

---

### 4.1 Check-in

---

#### I-CHK-01 · P0 · `public.checkins` does not exist; the only reachable check-in writer targets it
**Schema object:** `public.checkins` — **no such relation** (absent from the live dump and from all 123 migrations)
**Writers:** [`checkin_service.dart:18`](../apps/mobile/lib/features/checkins/data/checkin_service.dart#L18) (daily), [`:86`](../apps/mobile/lib/features/checkins/data/checkin_service.dart#L86) (weekly)
**Readers:** [`checkin_service.dart:42, :62, :112, :141`](../apps/mobile/lib/features/checkins/data/checkin_service.dart#L42), [`coach_dashboard_screen.dart:108`](../apps/mobile/lib/features/dashboard/presentation/coach_dashboard_screen.dart#L108)
**Expected contract:** a relation with `user_id, mood, energy, stress_level, sleep_hours, notes, checked_in_at, checkin_type`
**Actual contract:** none. Seven call sites against a relation that has never existed.
**Evidence:** `comm -23` of every `.from()` name against the 91 live tables + 5 views leaves exactly `{checkins, coach_tips}` (plus the `avatars` storage bucket). LIVE dump; reproduced by `npm run test:contract`.
**Root cause:** RC-7 — every call site returns `false`/`0`/`[]` from its `catch`, so a 404 is indistinguishable from "no data".
**Data-integrity impact:** **no check-in can be created by the application at all.** Downstream: coach review queue, compliance scoring, the at-risk roster, the Insights panel, the AI grounding packet and the check-in component of the 12 Circle Score all consume a structurally empty input.
**Existing migration responsible:** none — the table was never created.
**Recommended fix:** retire `checkin_service.dart`; repoint its callers at `WeeklyCheckinService`, which writes the real table and currently has **zero callers**. Do not create a `checkins` table without §9-Q1 being answered first.
**Product decision needed:** **YES — Q-1.** Is there a *daily* check-in distinct from the weekly one? The table comment on `weekly_checkins` records the Phase 0 ruling that it is *not* the authoritative source and that weekly behaviour is to be derived from daily data "in a later phase". That phase has no schema.
**Parallelizable:** no — blocks I-CHK-02/03/04.
**Cross-ref:** CON-01, E-CHK, EC-10 — **re-verified open** against the live schema.

---

#### I-CHK-02 · P0 · The coach check-in notification can never fire: its precondition has no writer
**Schema object:** trigger `notify_coach_on_checkin` `AFTER INSERT ON weekly_checkins` → `trg_notify_coach_on_checkin()`; column `weekly_checkins.coach_id`
**Writers of `coach_id`:** **none.** Not `submitWeeklyCheckin()`, not any migration, not any Edge Function, not any RPC. Only `supabase/seeds/test_accounts.sql:214` sets it.
**Readers:** the trigger body itself.
**Expected contract:** a submitted check-in notifies the client's coach.
**Actual contract:** the function's third statement is `IF v_coach_id IS NULL THEN RETURN NEW; END IF;` — it returns on every application-written row. The notification body then reads `NEW.weight_kg`, `NEW.energy_level` and `NEW.compliance_percent`, none of which the writer sets either, so even a row that got past the guard would render `Weight: —kg | Energy: —/5 | Compliance: —%`.
**Evidence:** live dump lines 3855–3872 (function body) and the `coach_id`-writer census above.
**Root cause:** the trigger was written against the *pre-existing* column family; the application writes the family migration `001` added. Same root as I-CHK-03.
**Data-integrity impact:** no data is corrupted, but a coach is never told a client checked in — **and the client-side notification was deliberately deleted in reliance on this trigger**: `weekly_checkin_service.dart:92` reads *"Coach notification (CHK-001) is handled server-side by the `trg_notify_coach_on_checkin` DB trigger, so no Dart-side insert here."* A working path was removed in favour of one that cannot run.
**Existing migration responsible:** `004_notifications_and_triggers.sql`.
**Recommended fix:** forward migration. Derive the coach inside the trigger from `coach_client_relationships` (as `trg_notify_on_workout_complete` already does) instead of trusting a column nobody writes, and build the body from the columns the writer actually sets. Setting `coach_id` at write time is the *worse* fix: it duplicates the relationship table.
**Product decision needed:** no.
**Parallelizable:** yes — independent of I-CHK-01.

---

#### I-CHK-03 · P1 · `weekly_checkins` carries two mutually exclusive column families
**Schema object:** `public.weekly_checkins` (23 columns)
**Family A** (pre-existing, `000`): `mood, energy, sleep_hours_avg, overall_score, submitted_at, feedback_message, feedback_recommendations, reviewed_at, coach_name, status, week_number, week_start_date`
**Family B** (added by `001`): `coach_id, weight_kg, energy_level, stress_level, sleep_hours, hunger_level, compliance_percent, notes`
**Writer:** [`weekly_checkin_service.dart:82`](../apps/mobile/lib/features/checkins/data/weekly_checkin_service.dart#L82) → family A **+ `stress_level` + `notes`**
**Readers:** `_fromRow()` → family A + `stress_level` ✅ · [`insights_provider.dart:74`](../apps/mobile/lib/features/insights/domain/insights_provider.dart#L74) → `energy_level, sleep_hours, weight_kg, stress_level` (family B) ❌ · `trg_notify_coach_on_checkin` → family B ❌ · `ai_adjust_nutrition` → `weight_kg` ❌ · `ai-coach/index.ts:46` → `select('*')`, half null
**Expected contract:** one representation of a check-in answer.
**Actual contract:** two, with one column (`stress_level`) accidentally shared. Three of the four metrics the Insights "recovery" card reads are `NULL` forever.
**Evidence:** live column list + writer/reader source, all quoted above.
**Root cause:** RC-5-shaped — the same domain concept modelled twice, never reconciled.
**Data-integrity impact:** no corruption; permanent partial nulls that read as "the user did not answer".
**Existing migration responsible:** `001_full_ecosystem.sql:32` and neighbours.
**Recommended fix:** pick one family, migrate the other's data into it, and drop the losers in a forward migration. Family B is the one every non-owner reader and every server-side consumer expects.
**Product decision needed:** **YES** — which family is canonical, and are `hunger_level`/`compliance_percent` (family B, no writer, no UI) part of the check-in form?
**Parallelizable:** no — I-CHK-02 and I-NUT-02's fixes both depend on the answer.
**Cross-ref:** E-CHK — **re-verified open**, now with the live column list.

---

#### I-CHK-04 · P1 · The QA fixtures write the opposite column family and the wrong status, masking I-CHK-02/03
**Schema object:** `supabase/seeds/test_accounts.sql:213–221`
**Writer:** the seed.
**Readers:** every check-in surface in QA.
**Expected contract:** a fixture exercises the same contract the application writes.
**Actual contract:** the seed writes `user_id, coach_id, week_number, week_start_date, weight_kg, energy_level, stress_level, sleep_hours, hunger_level, compliance_percent, notes, created_at` — **family B plus `coach_id`, and no family-A column at all**. It never sets `status`, so all three seeded rows default to `'pending'`.
**Evidence:** seed source vs the live `DEFAULT 'pending'::text` on `weekly_checkins.status`.
**Root cause:** the fixture was written against the reader surfaces, not against the writer.
**Data-integrity impact:** **QA verification of check-in is structurally misleading.** The coach dashboard and Insights look populated because they read family B, which only the seed writes; the coach review queue (`getSubmittedCheckinsForCoach()` filters `status = 'submitted'`) is **empty even with seeded check-ins**; and the notification trigger appears reachable in QA (the seed sets `coach_id`) while it is unreachable in production behaviour. Any manual QA pass on check-in will report the opposite of the truth in both directions.
**Existing migration responsible:** n/a — fixture.
**Recommended fix:** once I-CHK-03 is decided, rewrite the seed to produce exactly what `submitWeeklyCheckin()` produces, including `status = 'submitted'` for at least one row and `'reviewed'` for another. Until then, treat any QA result for check-in as unverified.
**Product decision needed:** no (follows I-CHK-03).
**Parallelizable:** no — follows I-CHK-03.
**New in this workstream.**

---

### 4.2 Nutrition

---

#### I-NUT-01 · P1 · `ai-coaching-engine` reads three `nutrition_logs` columns that do not exist
**Schema object:** `nutrition_logs` — the macro columns are `protein`, `carbs`, `fat`
**Writer:** [`nutrition_service.dart:53`](../apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L53) → `calories, protein, carbs, fat, amount_g, serving_unit, logged_at` ✅
**Reader:** [`ai-coaching-engine/index.ts:147`](../supabase/functions/ai-coaching-engine/index.ts#L147) → `select('calories, protein_g, carbs_g, fat_g')`
**Expected contract:** today's consumed macros, subtracted from the active plan to give `remaining_macros_today`.
**Actual contract:** the **entire query** fails — PostgREST validates the select list as a unit, so `calories` is lost too. `{ data: todays }` destructures to `null`, the error is discarded, `sum()` returns 0, and `remaining_*` equals the full daily target.
**Evidence:** LIVE — `GET /rest/v1/nutrition_logs?select=calories,protein_g&limit=1` → `400 {"code":"42703","hint":"Perhaps you meant to reference the column \"nutrition_logs.protein\"", "message":"column nutrition_logs.protein_g does not exist"}`.
**Root cause:** RC-7 plus a naming convention (`_g` suffix) borrowed from `client_nutrition_plans`, where it *is* correct.
**Data-integrity impact:** the meal-suggestion model is told, every day, for every user, that they have eaten nothing.
**Existing migration responsible:** `006`/`012`/`014` established `protein/carbs/fat`; the Edge Function was written against `client_nutrition_plans`' spelling.
**Recommended fix:** one-line rename in the Edge Function. No migration.
**Product decision needed:** no.
**Parallelizable:** yes.
**Cross-ref:** E-NUT — **re-verified open**, now with the live 400.

---

#### I-NUT-02 · P1 · `ai_adjust_nutrition()` is dead twice over — a missing column behind an unreachable guard
**Schema object:** `public.ai_adjust_nutrition(p_uid uuid)`
**Writers it depends on:** `weekly_checkins.weight_kg` — **no writer** (see I-CHK-03)
**Expected contract:** move a user's calorie target from their 5-week weight trend.
**Actual contract:** two independent failures, the second hidden by the first.
1. `select count(*) … where weight_kg is not null … ; if v_n < 2 then return; end if;` — with no writer for `weight_kg`, this returns for every application-created user.
2. If it ever passed, the next statement is `v_goal := coalesce(p.fitness_goal, p.goal, 'general')` where `p` is `user_profiles%rowtype`. **`user_profiles` has no column `goal`** — verified against the live `CREATE TABLE`. plpgsql raises `record "p" has no field "goal"` (`42703`) at execution.
**Evidence:** live dump lines 3860–3900; live `user_profiles` column list (78 columns, `fitness_goal`/`nutrition_goal`/`weight_goal_kg`/`goal_weight_kg`, no `goal`).
**Root cause:** RC-5 (duplicate goal representations) + I-CHK-03.
**Data-integrity impact:** nutrition auto-adjustment has never run. Because the function is *also* excluded from migration 116's EXECUTE allowlist, no client can invoke it, so the latent `42703` has never surfaced as an error anyone saw.
**Existing migration responsible:** `079_nutrition_autoadjust_and_coach_signals.sql`.
**Recommended fix:** forward migration replacing the function: drop `p.goal`, and source the weight trend from `weight_logs` (which *is* written) rather than from a check-in column nobody fills. Keep it off the client allowlist.
**Product decision needed:** **YES** — is body weight captured by the check-in or by `weight_logs`? Both tables model it.
**Parallelizable:** no — depends on I-CHK-03.

---

#### I-NUT-03 · P1 · `ai_adjust_nutrition()` overwrites the coach's prescription in place, under the coach's name
**Schema object:** `client_nutrition_plans`
**Writer:** the RPC's `UPDATE client_nutrition_plans SET calories_target=…, protein_g=…, carbs_g=…, fat_g=…, notes='Auto-adjusted from your weight trend (…)' WHERE id = v_plan.id`
**Readers:** [`nutrition_provider.dart:18`](../apps/mobile/lib/features/nutrition/domain/nutrition_provider.dart#L18), [`nutrition_service.dart:83`](../apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L83), `coach_program_service.dart:290`, `ai-coach/index.ts:44`, `ai-coaching-engine/index.ts:143`
**Expected contract:** an AI adjustment is attributable and reversible.
**Actual contract:** it mutates the coach's row. `coach_id` is left pointing at the coach, so the coach's name is now attached to numbers the engine wrote, **the coach's `notes` are destroyed**, and there is no record of the prior values. `client_nutrition_plans` already has an `is_active` flag and a `created_at` — the supersede-and-insert pattern the coach's own writer uses — and the RPC does not use it.
**Evidence:** live function body, final `update`.
**Root cause:** audit/history immutability was never a property of this table.
**Data-integrity impact:** silent, unrecoverable loss of a coach-authored prescription, misattributed. This is a professional-liability shape, not just a data shape.
**Existing migration responsible:** `079`.
**Recommended fix:** forward migration — supersede (`is_active=false`) and insert a new row with `coach_id = NULL` and a `notes` value that says the engine wrote it. Pairs naturally with the I-NUT-02 rewrite.
**Product decision needed:** **YES** — may the engine change a coach-assigned plan at all, or only a self-generated one?
**Parallelizable:** no — same function as I-NUT-02.

---

#### I-NUT-04 · P1 · No uniqueness on the active nutrition plan; every reader uses `maybeSingle()`
**Schema object:** `client_nutrition_plans` — PK on `id`, **no unique index on `(client_id) WHERE is_active`**
**Writers:** [`coach_program_service.dart:263–277`](../apps/mobile/lib/features/coach/data/coach_program_service.dart#L263) (deactivate-then-insert, **two non-atomic statements**); `generate_client_plan()` (same pattern, inside one function, so atomic); `ai_adjust_nutrition()` (in-place, see I-NUT-03)
**Readers:** four sites, **all** `.eq('is_active', true).maybeSingle()`; only the Edge Function adds `.order('created_at', …)`, which does not help.
**Expected contract:** at most one active plan per client.
**Actual contract:** nothing enforces it. Two active rows make PostgREST return **406** to `maybeSingle()` (it requests `application/vnd.pgrst.object+json`), which every caller catches and turns into "no plan" — silently reverting the client to the hard-coded defaults `{2000 kcal, 120 g protein}`.
**Evidence:** live constraint list for `client_nutrition_plans` (PK + two FKs only); reader source.
**Root cause:** an identity model that lives in application convention instead of in an index.
**Data-integrity impact:** two failure modes. (a) The coach's writer deactivates, then the insert fails (RLS, validation, connectivity) → the client has **no** active plan and silently sees defaults. (b) Any path that produces a second active row makes every reader fall back to defaults. A user following the app is then eating to numbers nobody prescribed.
**Existing migration responsible:** `023`/`024` created the table; no migration ever added the constraint.
**Recommended fix:** forward migration adding `CREATE UNIQUE INDEX … ON client_nutrition_plans (client_id) WHERE is_active` (after reconciling existing duplicates), and move the coach's deactivate+insert into a single `SECURITY DEFINER` RPC so it is atomic.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

### 4.3 Intelligence / AI

---

#### I-INT-01 · P0 · `ai-coaching-engine` selects `user_profiles.goal`; the whole profile query 400s
**Schema object:** `user_profiles` — **no column `goal`**
**Reader:** [`ai-coaching-engine/index.ts:123`](../supabase/functions/ai-coaching-engine/index.ts#L123) → `select('first_name, role, goal, gender, date_of_birth, height_cm, weight_kg, experience_level, membership_tier')`
**Expected contract:** the user's profile grounds every insight the engine generates.
**Actual contract:** `42703` → `profile` is `null` → `context.profile = profile ?? {}`. **Every** `daily_insight`, `weekly_review`, `goal_prediction`, `accountability`, `risk_assessment`, `progress_insight` and `meal_suggestion` is generated from an empty profile: no name, no gender, no age, no height, no weight, no experience level, no tier.
**Evidence:** live `user_profiles` DDL; PostgREST 400-before-401 ordering confirmed LIVE (§11.2).
**Root cause:** RC-5 — `fitness_goal` vs a `goal` that only ever existed in someone's head. Compounded by RC-7: the Edge Function destructures `{ data: profile }` and never inspects `error`.
**Data-integrity impact:** the product bible's first principle is personalised coaching; the personalisation input is empty for every user, every call.
**Existing migration responsible:** none — the column was never created.
**Recommended fix:** `goal` → `fitness_goal` in the select list. Additionally, make the engine surface a PostgREST error rather than coalescing it to `{}`.
**Product decision needed:** no.
**Parallelizable:** yes.

---

#### I-INT-02 · P0 · `ai-generate-workout` loses the user's injury data in a query that fails on two nonexistent columns
**Schema object:** `user_profiles` — no `goal`, **no `equipment`**
**Reader:** [`ai-generate-workout/index.ts:63`](../supabase/functions/ai-generate-workout/index.ts#L63) → `select('fitness_goal, goal, equipment, experience_level, training_location, has_injuries, injury_locations')`
**Expected contract:** the generator must know the user's injuries and contraindications before prescribing movement.
**Actual contract:** two unknown columns fail the request, and **`has_injuries`, `injury_locations`, `experience_level` and `training_location` are lost with them** — they were valid, they were in the same select list. `profile` is `null` and the generator proceeds.
**Evidence:** live `user_profiles` DDL; PostgREST 400 semantics confirmed LIVE.
**Root cause:** RC-5 (`goal`, `equipment` are duplicate/never-created spellings of `fitness_goal` and the equipment model that lives on `custom_exercises`) + RC-7.
**Data-integrity impact:** **safety.** The AI workout generator has never seen an injury flag. Migration `115` went to real trouble to derive `risk_score`/`risk_level`/`risk_flags` server-side from PAR-Q answers so that "any downstream training constraint must read this copy" — and the one downstream consumer that most needs it reads none of it.
**Existing migration responsible:** none — the columns were never created. `013_health_assessment.sql` created the injury columns the query drops.
**Recommended fix:** drop `goal` and `equipment` from the select list; add `risk_level`, `risk_flags`, `medical_conditions`. Treat a null profile as a hard error in this function, not as an empty object — a generator that cannot read contraindications must refuse, not guess.
**Product decision needed:** **YES** — should generation *fail closed* when the safety inputs are unavailable? This report recommends yes and does not decide it.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-INT-03 · P3 · Three `ai_insights.type` values are written and never read
**Schema object:** `ai_insights.type` (`text`, default `'daily_insight'`, **no CHECK**)
**Writers:** `ai-coaching-engine` writes `daily_insight`, `accountability`, `risk`, `progress`, `meal_suggestion`; `ai_adjust_nutrition()` writes `nutrition_adjustment`.
**Readers:** the client filters on `daily_insight`, `accountability`, `meal_suggestion` only.
**Actual contract:** `risk`, `progress` and `nutrition_adjustment` rows accumulate with no surface.
**Root cause:** an unconstrained vocabulary shared by two producers and one consumer.
**Data-integrity impact:** none; dead rows and a misleading "insights generated" count in the observability screen.
**Recommended fix:** either surface them or stop writing them; add a CHECK once the set is settled.
**Product decision needed:** **YES** — are risk and progress insights a shipped feature?
**Parallelizable:** yes.

---

#### I-INT-04 · P3 · AI context field-name drift
**Schema objects:** `workout_sessions`, `workout_feedback`, `cycle_logs`
**Reader:** `ai-coaching-engine/index.ts:168–172`
**Actual contract:** `recent_workouts` maps `w.title` — `workout_sessions` has `workout_title` and `workout_name`, not `title`, so every recent workout reaches the model unnamed. `recovery: feedback?.[0] ?? cycles?.[0]` puts either a `workout_feedback` row (`energy_level`, `difficulty`) **or** a `cycle_logs` row (`start_date`, `end_date`) into one field, so the model receives two incompatible shapes under one key. `recent_set_logs` maps `s.created_at`, which `workout_set_logs` does not have (see I-WRK-01).
**Root cause:** the AI context object is assembled by hand with no schema.
**Data-integrity impact:** silently degraded prompts; no corruption.
**Recommended fix:** define the context packet as a typed structure with explicit column names, and give `recovery` a discriminator.
**Product decision needed:** no.
**Parallelizable:** yes.
**Cross-ref:** F-18 (cycle data crossing the user-isolation boundary through this same function) — that finding stands and is not restated here.

---

### 4.4 Women's health

Workstream F audited this subsystem in depth (F-01…F-23) and its functional findings are
**not** restated. Two DB-contract observations complement it.

---

#### I-WMH-01 · P2 · `cycle_logs` has no uniqueness, no ordering constraint, and no overlap guard
**Schema object:** `public.cycle_logs` — PK on `id`, one FK, one index `(user_id, start_date DESC)`. **No unique constraint, no CHECK.**
**Writer:** [`cycle_service.dart:44`](../apps/mobile/lib/features/womens_health/data/cycle_service.dart#L44) `logPeriod()` — a plain `insert`
**Readers:** `getPeriods()`, `computeCycleStatus`, `ai-coaching-engine` (`recent(db,'cycle_logs',…)`)
**Expected contract:** one period per start date; `end_date >= start_date`; periods do not overlap.
**Actual contract:** none of the three is enforced. A double tap inserts two periods for one day. `endCurrentPeriod()` closes only *the most recent* open period, so a duplicate leaves an older one open forever, and cycle-length arithmetic then runs over a corrupted series.
**Evidence:** live constraint/index list for `cycle_*`. Note `cycle_symptoms` **does** have `UNIQUE (user_id, log_date)` and `cycle_settings` has `PRIMARY KEY (user_id)` — so two of the three tables in this module got an identity model and one did not.
**Root cause:** identity model left to the application.
**Data-integrity impact:** derived phase, fertile window and every piece of phase-gated guidance are computed from a series that can silently contain duplicates and never-closed periods.
**Existing migration responsible:** `033_womens_health.sql`.
**Recommended fix:** forward migration — `UNIQUE (user_id, start_date)`, `CHECK (end_date IS NULL OR end_date >= start_date)`, and after a dedupe pass an exclusion constraint on overlapping `[start_date, end_date]` ranges. Cheap, and it makes F-01/F-04 impossible rather than merely reported.
**Product decision needed:** no.
**Parallelizable:** yes.
**Complements:** F-01, F-04 (app-level). This is the database-level complement they did not cover.

---

#### I-WMH-02 · P3 · Cycle rows enter the AI context in the `recovery` slot
Covered as part of **I-INT-04**; recorded here so the women's-health domain index is complete. Cross-ref F-18.

---

### 4.5 Subscription / payment / session credits

---

#### I-PAY-01 · P1 · Session credits are granted non-idempotently from an at-least-once webhook
**Schema object:** `client_session_credits` — PK on `id`; **no unique constraint on `payment_id`** (or on anything else)
**Writer:** [`stripe-webhook/index.ts:130`](../supabase/functions/stripe-webhook/index.ts#L130) — a plain `insert`
**Readers:** the coach scheduling / session-consumption paths
**Expected contract:** one `checkout.session.completed` grants one credit block.
**Actual contract:** Stripe delivers webhooks at least once and retries on any non-2xx. Every other write in the same handler is idempotent by construction — `payments` is an `UPDATE … WHERE id`, `subscriptions` upserts on `stripe_subscription_id`, `coach_client_relationships` upserts on the party pair, `event_registrations` upserts on `(event_id,user_id)`. **Only the credit grant is a bare insert**, so a redelivery grants the sessions again.
**Evidence:** live constraint list for `client_session_credits` (PK + four FKs, zero UNIQUE); handler source.
**Root cause:** the one write in the handler that was not given a conflict target.
**Data-integrity impact:** a client can end up owed more coaching sessions than they paid for; the coach absorbs the difference. Money.
**Existing migration responsible:** `028_package_payments.sql`.
**Recommended fix:** forward migration adding `UNIQUE (payment_id)` (after deduping), then change the insert to `upsert … onConflict: 'payment_id'`. `payment_id` is nullable, so use a partial unique index `WHERE payment_id IS NOT NULL`.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-PAY-02 · P2 · Payment and subscription state vocabularies are unconstrained and inconsistently spelled
**Schema objects:** `payments.status` (default `'pending'`), `payments.kind` (default `'event_ticket'`), `subscriptions.status` (default `'incomplete'`), `subscriptions.kind`, `subscriptions.plan_tier` — **no CHECK on any of them**
**Writers:** the Stripe webhook writes `sub.status` **verbatim from the Stripe API** (`incomplete`, `trialing`, `active`, `past_due`, `canceled`, `unpaid`, `incomplete_expired`, `paused`) and `'canceled'` (one `l`) on deletion; `create-checkout` writes `payments.status='pending'`; the webhook writes `'paid'`.
**Readers:** the client filters `subscriptions.status in ('active','trialing')` and `payments.status = 'paid'`.
**Actual contract:** the database is a passthrough for a third party's enum. Elsewhere in the same schema the application writes `'cancelled'` (two `l`s) for `coach_client_relationships` and `class_bookings`. Two spellings of one concept coexist with nothing to catch a third.
**Root cause:** external vocabulary adopted without a boundary.
**Data-integrity impact:** low today — the readers use positive filters, so an unrecognised status is treated as inactive, which fails safe. It becomes a defect the moment any reader writes a negative filter (`.neq('status','cancelled')`).
**Recommended fix:** add CHECKs enumerating the accepted Stripe values (`NOT VALID` if legacy rows resist), and a single Dart/TS constant for each vocabulary.
**Product decision needed:** no.
**Parallelizable:** yes.

---

#### I-PAY-03 · Verified correct — `ON CONFLICT` targets · DERIVED
Recorded because it is the obvious next worry and it is **not** a defect. Every
`onConflict` string in the tree is backed by a real constraint:
`subscriptions_stripe_subscription_id_key`, `event_registrations_event_id_user_id_key`,
`class_bookings_class_id_user_id_key`, `cycle_symptoms_user_id_log_date_key`,
`weekly_checkins_user_week_unique`, `ai_profiles_pkey (user_id)`,
`cycle_settings_pkey (user_id)`. The webhook's
`onConflict: 'client_id,coach_id'` against `UNIQUE (coach_id, client_id)` is also correct
— Postgres infers the arbiter index from the *set* of columns, not their order.

---

### 4.6 User / profile / role

---

#### I-USR-01 · P1 · 53 of 143 foreign keys restrict deletes; program deletion and account deletion are both blocked
**Schema objects:** 53 FKs with no `ON DELETE` clause (i.e. `NO ACTION`), including `workout_program_assignments_program_id_fkey`, `workout_sessions_program_workout_id_fkey`, `workout_feedback_session_id_fkey`, `daily_scores_user_id_fkey`, `habit_logs_user_id_fkey`, `coaching_calls_*`, `event_registrations_user_id_fkey`
**Writer/actor:** [`coach_program_service.dart:179`](../apps/mobile/lib/features/coach/data/coach_program_service.dart#L179) `deleteProgram()`
**Expected contract:** the method's own comment — *"program_workouts cascade-delete via the FK ON DELETE CASCADE."*
**Actual contract:** the cascade to `program_workouts` is real, but `workout_program_assignments.program_id` restricts. **Any program that has been assigned to a client cannot be deleted**, and `deleteProgram()` has no error handling — the `23503` propagates to the UI. `deleteWorkout()` has the same shape via `workout_sessions.program_workout_id`.
**Evidence:** live constraint list, filtered for `FOREIGN KEY` without `ON DELETE` (53 of 143).
**Root cause:** delete semantics were decided per-table, never as a policy.
**Data-integrity impact:** the restrictions are *protecting* history correctly — the defect is that no caller expects them. Two concrete consequences:
* A coach cannot delete an assigned program and gets a raw Postgres error.
* **Account deletion is impossible.** `user_profiles.id → auth.users(id) ON DELETE CASCADE` means deleting an auth user cascades into `user_profiles`, which is then blocked by every restricting child FK. `help_center_screen.dart:45` tells users *"Go to Profile → Settings → Account → Delete Account. All your data is permanently removed within 30 days."* No such path exists anywhere in the tree, and if one were added it would fail on the first user who had ever logged a workout.
**Existing migration responsible:** distributed across `001`, `022`–`028`, `035`, `047`.
**Recommended fix:** two separable pieces. (a) `deleteProgram()` must archive (`is_template=false` + a status), not delete — a program a client has trained is history. (b) Account deletion needs a designed erasure path (a `SECURITY DEFINER` RPC that anonymises or cascades in dependency order), not an FK change.
**Product decision needed:** **YES, two.** Is program deletion "archive" or "erase"? And what is the account-deletion contract the Help Center already promises — hard delete, or anonymise-and-retain?
**Parallelizable:** yes (the two halves are independent).
**Cross-ref:** G — App Store readiness records the account-deletion requirement; this is its database-side reason.

---

#### I-USR-02 · P2 · `user_profiles.email` can never be updated after creation
**Schema object:** `user_profiles.email` (`text NOT NULL`); trigger `trg_profile_privilege` → `enforce_profile_privilege()`
**Writer:** `handle_new_user()` at signup (runs with `auth.uid()` null, so the trigger's service-role early return applies)
**Actual contract:** for every authenticated update the trigger executes `NEW.email := OLD.email;` in its "PINNED: server-derived, silently held" block. Pinning is correct — email is identity, not profile text — but **nothing else keeps it in step with `auth.users.email`.** A user who changes their login email leaves a stale address in `user_profiles` forever.
**Readers of the stale value:** `getSubmittedCheckinsForCoach()`'s embed, `admin_recent_users()`, `vendor_service.getRegistrations()`, the coach client directory.
**Evidence:** live function body of `enforce_profile_privilege()`.
**Root cause:** the pin was added (migration `115`) without a compensating sync path.
**Data-integrity impact:** coaches and admins see and may contact an address the user has abandoned.
**Existing migration responsible:** `115_profile_privilege_boundary.sql`.
**Recommended fix:** forward migration — a trigger on `auth.users` `AFTER UPDATE OF email` that writes through to `user_profiles.email`, mirroring `handle_new_user()`'s existing `SECURITY DEFINER` shape.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-USR-03 · P2 · `user_profiles` models five concepts twice
**Schema object:** `public.user_profiles`, 78 columns
| Concept | Spellings |
|---|---|
| current body weight | `weight_kg` · `current_weight_kg` |
| target body weight | `weight_goal_kg` (default 0) · `goal_weight_kg` (null) |
| training experience | `fitness_level` · `experience_level` (`NOT NULL DEFAULT ''`) |
| age | `age` · `date_of_birth` |
| self-description | `bio` · `coach_bio` (`NOT NULL DEFAULT ''`) |
| training goal | `fitness_goal` · `nutrition_goal` · a `goal` that **does not exist** but two Edge Functions read (I-INT-01/02) |
**Readers disagree:** `predict_client` (migration `095`) reads `weight_kg, weight_goal_kg, fitness_goal`; `ai-coaching-engine` reads `weight_kg, experience_level`; `profile_screen.dart` computes weight progress from a different pair.
**Actual contract:** which of each pair is authoritative is undefined, and the two defaults differ (`weight_goal_kg` defaults to `0`, which reads as a real target of zero kilograms).
**Root cause:** RC-5, at column granularity.
**Data-integrity impact:** goal-progress arithmetic can divide by, or aim at, `0`. Different surfaces show different numbers for the same user.
**Recommended fix:** choose one of each pair, backfill, and drop the loser in a forward migration. `weight_goal_kg`'s `DEFAULT 0` should go regardless — an unset goal is `NULL`.
**Product decision needed:** **YES** — one ruling covers all five pairs.
**Parallelizable:** no — I-INT-01/02 and I-NUT-02 all reference the goal pair.

---

### 4.7 Notifications / messages

---

#### I-NOT-01 · P1 · `messages` has no `metadata` column; every chat image message is silently discarded after upload
**Schema object:** `public.messages` — `id, conversation_id, sender_id, content, is_read, sent_at`. **No `metadata`.**
**Writer:** [`messaging_service.dart:101`](../apps/mobile/lib/features/messaging/data/messaging_service.dart#L101) — `if (metadata != null) row['metadata'] = metadata;`
**Caller:** [`chat_screen.dart:157`](../apps/mobile/lib/features/messaging/presentation/chat_screen.dart#L157) — `metadata: {'image_url': publicUrl}` after uploading to the `chat-media` bucket
**Expected contract:** an image message is a message row carrying the image URL.
**Actual contract:** the insert 400s on the unknown column; `sendMessage()` returns `false`; the caller has already uploaded the file. The image sits in storage, orphaned, and the message never exists. **Text messages work** — the key is only added when `metadata != null` — so the defect is invisible in ordinary use and invisible to the message-bubble widget tests, which construct their own model objects.
**Evidence:** live `messages` DDL; call-site source.
**Root cause:** RC-7. Note this defect is **not** detectable by the new contract guard, because the key is assigned by index rather than written in an object literal — stated in the guard's README so the gap is not mistaken for coverage.
**Data-integrity impact:** user-authored content is destroyed, with a success-shaped UI path and an orphaned storage object per attempt.
**Existing migration responsible:** `001`/`003` created `messages` without `metadata`.
**Recommended fix:** forward migration `ALTER TABLE messages ADD COLUMN IF NOT EXISTS metadata jsonb`. The column is genuinely wanted — the widget layer already renders `imageUrl`.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-NOT-02 · P1 · `may_notify()` rejects the community and class notifications the app sends
**Schema object:** policy `notify a known counterparty` on `notifications` → `may_notify(recipient)`
**Writers blocked:** [`live_community_service.dart:129`](../apps/mobile/lib/features/community/data/live_community_service.dart#L129) (comment → post author), [`live_class_service.dart:173`](../apps/mobile/lib/features/classes/data/live_class_service.dart#L173) (waitlist promotion → promoted member)
**Expected contract:** the post author is told someone commented.
**Actual contract:** `may_notify()` returns true only when the recipient is the caller, a coach/client counterparty, a conversation partner, a coaching-call counterparty, or a team member. **Two community members have none of those relationships**, so the insert is rejected and both call sites swallow it (`catch (_) { /* ignore notification failures */ }`).
**Evidence:** live `may_notify()` body and the `notifications` INSERT policy.
**Root cause:** migration `118` closed a real hole (anyone could notify anyone) with a relationship allowlist that did not enumerate the community and class relationships.
**Data-integrity impact:** none to stored data. Two notification features are dead, introduced as a regression by a Phase 1 migration.
**Existing migration responsible:** `118_security_sweep.sql`.
**Recommended fix:** forward migration extending `may_notify()` with the two missing relationships — "the recipient authored the post the caller is commenting on" and "the recipient and caller are booked into the same class". Keep it an allowlist; do not widen to `true`.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-NOT-03 · P2 · Two triggers notify the coach of the same completed workout
**Schema objects:** `notify_on_workout_complete` → `trg_notify_on_workout_complete()` **and** `trg_notify_coach_workout_complete` → `notify_coach_workout_complete()`, both `AFTER UPDATE ON workout_sessions`
**Actual contract:** both fire on the same `status → 'completed'` transition, both look up the client's active coach, and both insert a coach notification — with **different `type` values** (`'client_workout'` vs `'workout_completed'`), different titles, and different source columns (`workout_name` vs `workout_title`). The coach receives two notifications per workout, worded differently.
**Evidence:** live trigger list and both function bodies.
**Root cause:** a later migration added a second implementation instead of replacing the first.
**Data-integrity impact:** duplicate rows in `notifications`; coach notification counts are double.
**Recommended fix:** forward migration dropping one trigger. Keep `trg_notify_on_workout_complete` — it also notifies the client, and it uses `insert_notification()` rather than a raw insert.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-NOT-04 · P1 · A conversation participant can rewrite the other person's message text
**Schema object:** policy `recipients can mark messages read` — `FOR UPDATE TO authenticated USING (conversation_id IN (…participant…))`, **no `WITH CHECK`, no column restriction**
**Writer:** `markAsRead()` updates only `is_read`.
**Actual contract:** for `UPDATE`, an omitted `WITH CHECK` reuses `USING`. The policy therefore permits **any participant to update any column of any message in the conversation**, including `content` and `sender_id` of a message they did not write. `weekly_checkins` got exactly this protection in migration `114` (`enforce_checkin_authorship`); `messages` never did.
**Evidence:** live policy text; no trigger on `messages` in the live trigger list.
**Root cause:** the policy's name states its intent; its predicate does not encode it.
**Data-integrity impact:** **audit/history immutability failure on user-authored content.** A coach could silently rewrite a client's message — the exact class of thing a coaching product must be able to deny.
**Existing migration responsible:** `001`/`003`; untouched by `118`.
**Recommended fix:** forward migration — a `BEFORE UPDATE` trigger on `messages` that permits only `is_read` to change unless `auth.uid() = OLD.sender_id`, modelled directly on `enforce_checkin_authorship()`.
**Product decision needed:** **YES** — may a sender edit or delete their own message after sending?
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-NOT-05 · P2 · `conversations` has no unique constraint on the participant pair
**Schema object:** `public.conversations` — PK on `id` only
**Writers:** `getOrCreateConversationWith()` and `getOrCreateCoachClientConversation()` — **two independent check-then-insert paths** for the same pair
**Actual contract:** the read and the insert are separate round trips with no arbiter index, so two devices, or the two entry points, can both create a thread for one pair. The messages then split across threads and each participant sees half a conversation.
**Evidence:** live constraint list for `conversations`.
**Root cause:** identity model in application code; the pair is unordered, which is why an index was never obvious.
**Data-integrity impact:** conversation history silently fragments.
**Recommended fix:** forward migration — `CREATE UNIQUE INDEX ON conversations (least(participant_1,participant_2), greatest(participant_1,participant_2))`, and collapse both Dart paths onto one `SECURITY DEFINER` get-or-create RPC.
**Product decision needed:** no.
**Parallelizable:** yes.

---

#### I-NOT-06 · P3 · The `notifications.type` vocabulary has 20 producers and 8 handled cases
**Schema object:** `notifications.type` (`text NOT NULL DEFAULT 'general'`, **no CHECK**)
**Producers:** DB triggers emit `challenges, client_workout, coach_request, message, messages, today_score, weekly_checkins, workout, workout_completed, pr_achieved`; the client emits `checkin, class, community, upload, coach_video, coaching_ended, habits_assigned, new_client, nutrition_assigned, program_assigned, request_approved, request_declined, session_booked, session_cancelled, workout_feedback`; the AI engine emits `ai_accountability`.
**Reader:** [`notifications_screen.dart:331–358`](../apps/mobile/lib/features/notifications/presentation/notifications_screen.dart#L331) handles 15 literals across 8 cases and falls through to a generic bell for everything else.
**Actual contract:** more than half of all notification types render with no icon or colour of their own — including `client_workout` and `workout_completed`, the two most frequent coach notifications (I-NOT-03).
**Root cause:** shared vocabulary with no single definition, split across SQL and Dart.
**Recommended fix:** one enumerated constant (Dart) plus a CHECK, added together so neither side can drift.
**Product decision needed:** no.
**Parallelizable:** yes.

---

### 4.8 Community / marketplace / events

---

#### I-COM-01 · P0 · Event registration writes a nonexistent column, then fabricates a ticket the user never received
**Schema object:** `event_registrations` — the code column is **`qr_code`** (`DEFAULT encode(gen_random_bytes(16),'hex')`). **There is no `ticket_code`.**
**Writer:** [`event_ticket_screen.dart:61`](../apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart#L61) — inserts `ticket_code`
**Readers:** [`event_ticket_screen.dart:41`](../apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart#L41), [`vendor_service.dart:41`](../apps/mobile/lib/features/vendor/data/vendor_service.dart#L41)
**Expected contract:** registering writes a row; the ticket screen shows that row's code.
**Actual contract:** the insert 400s. The `catch` is labelled **"Demo fallback"** and does this:
```dart
final code = 'TKT-DEMO-${…millisecondsSinceEpoch…}';
setState(() { _registered = true; _ticketCode = code; });
```
The user is shown a ticket code that exists nowhere, and told they are registered. On the next screen load, `_checkRegistration()` also 400s, so `_registered` is never restored — the ticket vanishes.
**Evidence:** live `event_registrations` DDL; call-site source; reproduced by `npm run test:contract`.
**Root cause:** RC-7, in its most damaging form — the error handler manufactures a plausible success.
**Data-integrity impact:** **fabricated user-facing state with no backing row.** A user believes they hold a ticket to an event they are not registered for; the vendor's attendee list will not contain them (and 400s anyway, I-COM-02).
**Existing migration responsible:** `021_event_sessions.sql` created `qr_code`.
**Recommended fix:** `ticket_code` → `qr_code` at all three sites and **delete the demo fallback** — a failed registration must fail visibly. The paid path (`create-checkout` → webhook → `event_registrations` upsert) is correct and unaffected; this is the free-registration path.
**Product decision needed:** no. (The "Demo fallback" pattern warrants a repo-wide sweep — see §6 RC-9.)
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-COM-02 · P1 · The vendor attendee list throws on the same nonexistent column
**Schema object:** `event_registrations.ticket_code`
**Reader:** [`vendor_service.dart:41`](../apps/mobile/lib/features/vendor/data/vendor_service.dart#L41) — `select('id, status, checked_in_at, registered_at, ticket_code, user_id, user_profiles(...)')`
**Actual contract:** 400, and unlike the client sites this one has **no `try`/`catch`** — the `PostgrestException` propagates. The vendor's attendee list for any event fails outright.
**Evidence:** as I-COM-01.
**Recommended fix:** same rename.
**Product decision needed:** no. **Parallelizable:** yes (same edit as I-COM-01).

---

#### I-COM-03 · P1 · Global exercise publishing has no moderation gate, and the moderation tool is broken
**Schema object:** `custom_exercises.submission_status` (`text`, **default `NULL`**, no CHECK), `visibility`, and a nonexistent `approved_by`
**Writers:** `submitForGlobalLibrary()` writes `submission_status='approved'` **and** `visibility='global'` in one step — its own comment says *"Platform-wide publishing: goes live for all clients immediately."* `approveGlobalExercise()` writes `submission_status, visibility, approved_by, approved_at`.
**Readers:** `getPendingGlobalSubmissions()` filters `submission_status = 'pending'`; the `exercises` view and migration `005`'s RLS both gate on `visibility='global' AND submission_status='approved'`; `detect_pr_on_set_log()` gates on the same pair.
**Expected contract:** migration `050`'s own header — *"Coaches submit exercises to the global library (`submission_status='pending'`) … admins flip `submission_status`."* Migration `005` documents the domain as `null | pending | approved | rejected`.
**Actual contract:** three failures compounding.
1. **Nothing ever writes `'pending'`.** The submit path writes `'approved'` directly, so the admin queue is permanently empty.
2. **The publish is immediate and unreviewed** — a coach makes an exercise visible to every client on the platform with one tap.
3. **`approved_by` does not exist** (the column is `last_reviewed_by`), so `approveGlobalExercise()` 400s and returns `false` — the admin approve button silently does nothing even for a row that somehow reached `'pending'`.
**Evidence:** live `custom_exercises` DDL (`submission_status`, `submitted_at`, `approved_at`, `last_reviewed_at`, `last_reviewed_by` — no `approved_by`); migration `005:32` and `050:3` comments; call-site source. Reproduced by `npm run test:contract`.
**Root cause:** the state machine was designed in migrations `005`/`050` and then bypassed by the client.
**Data-integrity impact:** unreviewed content reaches every user. `detect_pr_on_set_log()` also trusts the same gate, so an unreviewed exercise immediately participates in PR detection.
**Existing migration responsible:** `005_custom_exercises.sql`, `050_admin_exercise_moderation.sql`.
**Recommended fix:** (a) `approved_by` → `last_reviewed_by`. (b) `submitForGlobalLibrary()` writes `submission_status='pending'` and leaves `visibility` alone. (c) Forward migration adding `CHECK (submission_status IS NULL OR submission_status IN ('pending','approved','rejected'))` and a trigger forbidding `visibility='global'` unless `submission_status='approved'` — so the gate cannot be bypassed from any client again.
**Product decision needed:** **YES** — is global publishing moderated? The migrations say yes and the app says no. This report does not decide it.
**Parallelizable:** no — (b) and (c) must land together or the library is either frozen or ungated.
**New in this workstream.**

---

#### I-COM-04 · P1 · Class capacity, waitlist and enrolment are non-functional for members because three RLS-scoped operations are treated as global
**Schema objects:** `class_bookings` (policies `users manage own bookings` = `user_id = auth.uid()`; `coaches read bookings`), `classes` (policy `coaches manage classes` = `coach_id = auth.uid()`), `classes.current_enrolled`
**Actor:** [`live_class_service.dart`](../apps/mobile/lib/features/classes/data/live_class_service.dart) — `bookClass()`, `cancelBooking()` → `_promoteFromWaitlist()` → `_confirmedCount()`, `_syncEnrollment()`
**Expected contract:** book until capacity, then waitlist; a cancellation promotes the earliest waitlisted member; `current_enrolled` tracks confirmed bookings.
**Actual contract:** all three run as the acting member, and RLS scopes each of them to that member's own rows.
* `_confirmedCount()` selects **every** confirmed booking for the class; a member sees only their own → the count is 0 or 1 → `bookClass()` never reaches `maxCapacity` → **nothing is ever waitlisted**.
* `_promoteFromWaitlist()` selects another member's waitlisted booking → `null` → returns; even if it had one, `update class_bookings … .eq('id', next['id'])` matches 0 rows under the same policy — PostgREST returns 200 with an empty result, so **the failure is invisible**.
* `_syncEnrollment()` updates `classes.current_enrolled`, which only the class's coach may write → a member's call silently updates 0 rows, so the denormalised counter drifts permanently.
**Evidence:** live policies for `class_bookings` and `classes`; service source lines 118–179.
**Root cause:** aggregate and cross-user operations written as client-side queries against per-user RLS. An `UPDATE` that matches nothing is not an error in PostgREST, so RC-7 applies without even a `catch`.
**Data-integrity impact:** classes can be overbooked past `max_capacity`; `current_enrolled` is wrong; a cancelled seat is never offered to anyone.
**Existing migration responsible:** `031_classes_seed_and_price.sql`, and `118` for the `coaches read bookings` policy.
**Recommended fix:** forward migration moving capacity, promotion and enrolment into one `SECURITY DEFINER` RPC (`book_class(class_id)` / `cancel_booking(class_id)`) that does the counting and promotion server-side under a single transaction, and maintain `current_enrolled` with a trigger on `class_bookings` rather than from the client.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-COM-05 · P2 · `community_posts.likes_count` / `comments_count` have no writer
**Schema object:** `community_posts.likes_count`, `comments_count` (`integer DEFAULT 0`)
**Writers:** **none** — no trigger on `post_reactions` or `post_comments` in the live trigger list, and no `update` in the client.
**Readers:** none today; the UI counts the embedded arrays instead.
**Actual contract:** two columns permanently `0`, sitting in the table that most invites a "just read the counter" optimisation.
**Recommended fix:** either add the maintaining triggers (the `update_pod_member_count()` trigger on `accountability_pod_members` is the pattern already in the schema) or drop the columns.
**Product decision needed:** no. **Parallelizable:** yes.

---

#### I-COM-06 · P2 · `toggleReaction()` races its own unique constraint with no error handling
**Schema object:** `post_reactions_post_id_user_id_key UNIQUE (post_id, user_id)`
**Writer:** `live_community_service.dart:92–108` — select, then delete-or-insert, with no `catch`
**Actual contract:** two rapid taps (or two devices) both observe "no reaction" and both insert; the second raises `23505` and the exception reaches the UI. The constraint is correct; the writer does not use it.
**Recommended fix:** `upsert … onConflict: 'post_id,user_id'` for the like, and an unconditional delete for the unlike — no read first.
**Product decision needed:** no. **Parallelizable:** yes.

---

### 4.9 Workout — intersections only

Session integrity, set identity and the prescription contract were settled by Phase 2 and
migrations `103`–`108`/`119`–`121`; see [`WORKOUT_DOMAIN_CONTRACT.md`](WORKOUT_DOMAIN_CONTRACT.md).
Only contracts that cross into another domain are reported.

---

#### I-WRK-01 · P1 · `workout_set_logs.created_at` does not exist; every progression chart is empty
**Schema object:** `workout_set_logs` — the timestamp column is **`logged_at`**
**Writer:** `workout_service.dart:139` ✅ (does not write a timestamp; the default applies)
**Reader:** [`workout_service.dart:236`](../apps/mobile/lib/features/workout/data/workout_service.dart#L236) `getExerciseProgression()` — `select('weight_kg, reps, created_at').order('created_at')`, then `row['created_at'].substring(0,10)`
**Actual contract:** 400 → `catch` → `return []`. **Exercise progression is empty for every exercise, for every user, permanently.** `ai-coaching-engine` reads the same nonexistent field for `recent_set_logs` (I-INT-04).
**Evidence:** live `workout_set_logs` DDL; reproduced by `npm run test:contract`.
**Root cause:** RC-7 plus an inconsistent timestamp naming convention across the schema (`logged_at`, `created_at`, `sent_at`, `submitted_at`, `booked_at`, `registered_at`, `joined_at`).
**Data-integrity impact:** no corruption. The single most motivating screen in a strength product shows nothing, and has always shown nothing.
**Existing migration responsible:** `051_set_log_upsert.sql` and neighbours.
**Recommended fix:** `created_at` → `logged_at` at both sites.
**Product decision needed:** no. **Parallelizable:** yes.
**New in this workstream.**

---

#### I-WRK-02 · P2 · PR detection is `AFTER INSERT` only, while the writer is update-then-insert
**Schema object:** trigger `trg_detect_pr` `AFTER INSERT ON workout_set_logs`
**Writer:** `workout_service.dart:130–147` — deliberately `UPDATE … WHERE session_id AND set_id`, and only `INSERT` when that matched nothing (documented at `:127` as working around databases where the partial unique index cannot serve as an `ON CONFLICT` target).
**Actual contract:** correcting a set **upward** — the exact moment a personal record is realised, and the one the set-editing UI exists for — takes the `UPDATE` path and never fires the trigger. Only the first write of a set can produce a PR.
**Evidence:** live trigger definition; writer source.
**Root cause:** a BEFORE/AFTER assumption that predates the update-then-insert writer introduced with the `set_id` identity model.
**Data-integrity impact:** missed PR notifications for client and coach. No corruption — `detect_pr_on_set_log()` is idempotent-ish via its 2-hour dedup window, so extending it to `UPDATE` is safe.
**Existing migration responsible:** `049_workout_complete_and_pr_notifications.sql`, `056_pr_respects_flag.sql`.
**Recommended fix:** forward migration — `AFTER INSERT OR UPDATE OF weight_kg`.
**Product decision needed:** no. **Parallelizable:** yes.
**New in this workstream.**

---

#### I-WRK-03 · P2 · `workout_sessions.program_workout_id` has no writer
**Schema object:** `workout_sessions.program_workout_id uuid` → FK to `program_workouts(id)` (`NO ACTION`)
**Writers:** **none** — the string does not appear anywhere in `apps/mobile/lib`, `apps/api/src` or `supabase/functions`.
**Readers:** none.
**Actual contract:** a session cannot be attributed to the program day it was performed against. `coach_client_workout_stats` therefore counts sessions per client but cannot report adherence *to the assigned program*, and `evaluate_week`/`assemble_weekly_review` cannot tie performed work to prescribed work.
**Evidence:** live DDL + a repo-wide grep.
**Root cause:** the link was modelled and never wired.
**Data-integrity impact:** program adherence — the core coach-facing metric — is not derivable. Also renders the `NO ACTION` FK inert, which is why `generate_client_plan()`'s delete of self-generated programs does not currently fail (see I-USR-01; it **will** begin failing the moment this column is populated).
**Recommended fix:** populate it when a session is started from a program day. Sequence it *with* the I-USR-01 delete-semantics decision, not before.
**Product decision needed:** **YES** — coupled to I-USR-01.
**Parallelizable:** no.
**New in this workstream.**

---

### 4.10 Legacy and dead objects

---

#### I-LEG-01 · P1 · "A completed workout" is modelled twice and dual-written non-atomically
**Schema objects:** `workout_logs` (legacy: `workout_id uuid`, `workout_title`, `duration_minutes`, `calories_burned`, `category`, `completed_at`) and `workout_sessions` (current: `workout_id **text**`, `workout_title`, `status`, `duration_seconds`, `workout_snapshot`, …)
**Writers:** [`active_workout_screen.dart:608`](../apps/mobile/lib/features/workout/presentation/active_workout_screen.dart#L608) writes **both** — `logWorkout()` inserts a `workout_logs` row *and* the session is completed — as two separate requests with no transaction.
**Readers split cleanly down the middle:** `workout_logs` → streak, weekly count, total count, Insights, compliance, coach dashboard. `workout_sessions` → `coach_client_workout_stats`, `ai-coaching-engine`, `trg_notify_on_workout_complete`, PR detection.
**Actual contract:** two sources of truth for "did you train", written non-atomically, consumed by disjoint surfaces. If either write fails the two disagree permanently, and nothing reconciles them. The `workout_id` columns even have **different types** (`text` vs `uuid`), so the two records cannot be joined.
**Evidence:** live DDL for both; the writer and the eight reader sites.
**Root cause:** RC-5 at table granularity — the legacy model was never retired.
**Data-integrity impact:** the user's streak and the coach's completion rate are computed from different tables and can disagree. `workout_logs` has **no server-side writer at all**, so anything the DB derives ignores it.
**Existing migration responsible:** `001` (`workout_logs`) vs `035`/`047`/`103`+ (`workout_sessions`).
**Recommended fix:** retire `workout_logs`. Repoint the six client readers at `workout_sessions` (`status='completed'`), backfill any `workout_logs` row with no matching session, then drop the table in a forward migration. Until then, do not add readers to either.
**Product decision needed:** **YES** — confirm `workout_sessions` is canonical and that pre-`035` `workout_logs` history must be preserved.
**Parallelizable:** no — six readers move together.

---

#### I-LEG-02 · P2 · Four relations and two columns are fully dead
| Object | Writers | Readers | Status |
|---|---|---|---|
| `workouts` (10 cols) | none anywhere | none anywhere | fully dead; still the FK target of `workout_logs.workout_id` |
| `exercise_reviews` | none | none | fully dead |
| `exercise_analytics` | 1 DB writer | **none** | write-only |
| `score_cycles` | 2 DB writers | **none** | write-only; has `UNIQUE (user_id, period)` |
| `community_posts.likes_count/comments_count` | none | none | see I-COM-05 |
| `workout_sessions.program_workout_id` | none | none | see I-WRK-03 |
**Evidence:** a census of every `INSERT INTO`/`FROM`/`JOIN` in the live function bodies crossed with every `.from()` in the tree.
**Data-integrity impact:** none directly. Each is a surface a future reader can adopt believing it is populated — which is exactly how `likes_count` would become a defect.
**Recommended fix:** drop `workouts` and `exercise_reviews` in a forward migration (after confirming `workout_logs.workout_id` is always `NULL`, which it is — no writer sets it). Decide whether `exercise_analytics` and `score_cycles` have a consumer coming.
**Product decision needed:** **YES** for `exercise_analytics` and `score_cycles` only.
**Parallelizable:** yes.

---

#### I-LEG-03 · P2 · `coach_tips` is read and has never existed
**Schema object:** `public.coach_tips` — no such relation
**Reader:** [`coach_provider.dart:64`](../apps/mobile/lib/features/coach/domain/coach_provider.dart#L64) `coachTipProvider` — `select('id, content, category').eq('coach_id',…).eq('active',true)`
**Actual contract:** 404, swallowed by `catch (_) { return null; }`. The "Today's tip from your coach" card is empty for every user and always has been.
**Evidence:** table census; reproduced by `npm run test:contract`.
**Recommended fix:** delete the provider, or create the table. **Product decision needed:** **YES** — is coach tips a feature? No document in `docs/` mentions it.
**Parallelizable:** yes.
**Cross-ref:** MASTER §291, EC-10 — **re-verified open**.

---

### 4.11 Migration and type hygiene

---

#### I-MIG-01 · P1 · Migrations 113–122 are applied to QA but absent from the remote migration history
**Schema object:** `supabase_migrations.schema_migrations` on QA
**Evidence:** LIVE — `supabase migration list --linked` prints Local `113`…`122` with the **Remote column blank** for all ten, while §3.3 confirms every object those migrations create exists in the database.
**Expected contract:** applied migrations are recorded, so `db push` is a no-op and `db reset` is reproducible.
**Actual contract:** the DDL was applied out of band (SQL editor or a direct connection) without recording a history row.
**Root cause:** an out-of-band apply that was never followed by `supabase migration repair`.
**Data-integrity impact:** the next `supabase db push` will **re-run all ten against QA**. That is survivable *today* — §7.2 verifies all ten are idempotent — but the property is undocumented and one non-idempotent statement in a future edit would corrupt QA. It also means the history table cannot be trusted to answer "what is deployed", which is precisely the question that matters when 113–118 are the security migrations and production's state is unknown.
**Existing migration responsible:** n/a — process.
**Recommended fix:** `supabase migration repair --status applied 113 114 115 116 117 118 119 120 121 122` against QA. **Do not** do this for production without first establishing what production actually has.
**Product decision needed:** no.
**Parallelizable:** yes — and it should be done first, because every other forward migration recommended in this report will be pushed through the same broken bookkeeping.
**New in this workstream.**

---

#### I-MIG-02 · P2 · Both `ALTER`-added CHECK constraints are `NOT VALID`, and 119 may have left rows nobody looked at
**Schema objects:** `program_workouts_exercises_canonical` and `workout_sessions_status_known` — the **only** two `ALTER`-added CHECKs in the schema, both `NOT VALID`
**Actual contract:** `NOT VALID` is a deliberate, well-documented choice in both migrations — new writes are constrained, historical rows are not re-checked. But migration `119` also emits a `RAISE WARNING` naming any `program_workouts` row that survived canonicalisation still non-canonical, with a query to find them. **A warning in a CLI apply is easy to miss, and there is no record in `docs/` that anyone ran that query.**
**Evidence:** live constraint list (`NOT VALID` on both); `119:308–328`; `120:145–157`.
**Root cause:** none — this is correct migration practice with an open follow-up.
**Data-integrity impact:** unknown, and that is the point. Any surviving non-canonical `exercises` payload is a prescription the reader will interpret with the pre-119 ambiguity (`weight` vs `weight_kg`, `0`-for-unknown load).
**Recommended fix:** run `SELECT id, program_id, title FROM program_workouts WHERE NOT public.is_canonical_exercise_prescription(exercises)` against QA, repair or delete what it returns, then `ALTER TABLE … VALIDATE CONSTRAINT`. Same for `workout_sessions_status_known`. **Not done in this workstream** — repair is a write, and §13 records that no write was made.
**Product decision needed:** possibly — depends what the query returns.
**Parallelizable:** yes.

---

#### I-MIG-03 · P2 · `CREATE OR REPLACE FUNCTION` silently drops the `search_path` pin
**Schema objects:** all 131 functions
**Actual contract:** `search_path` is a *property of the function*, re-declared on every `CREATE OR REPLACE`. Migrations `119` and `120` create their functions **without** `SET search_path`; migration `122` re-pins them by `ALTER`. Live state is correct (131/131 pinned, §3.4) **only because 122 runs last.**
**Evidence:** `120:159` (`RETURNS trigger LANGUAGE plpgsql AS $$` — no `SET`) vs the live dump for the same function (`SET "search_path" TO 'public', 'pg_temp'`).
**Root cause:** a security property enforced by a trailing sweep rather than at the point of definition. The identical shape as RC-3, one level up.
**Data-integrity impact:** none today. The hazard is structural: any migration `123`+ that does `CREATE OR REPLACE FUNCTION` without the `SET` clause unpins that function, and nothing fails. `122` is a one-time sweep, not a guard.
**Existing migration responsible:** `119`, `120`, `122`.
**Recommended fix:** two things, not one. (a) A standing test — the `function-search-path.sql` fixture already in `supabase/tests/security/` should be wired into a suite that runs on every change, so an unpinned function fails immediately. (b) `SET search_path` written inline in every future `CREATE OR REPLACE FUNCTION`; the sweep is a backstop, not the mechanism.
**Product decision needed:** no.
**Parallelizable:** yes.
**New in this workstream.**

---

#### I-TYP-01 · P2 · Nine column names carry different types in different tables
| Column | Types | Consequence |
|---|---|---|
| `exercise_id` | **`text`** in `workout_set_logs` · `uuid` in 13 exercise tables | no FK is possible from a logged set to the library; every join must cast |
| `workout_id` | **`text`** in `workout_sessions` · `uuid` in `workout_logs` | the two completed-workout records (I-LEG-01) cannot be joined |
| `sleep_hours` | **`text`** in `user_profiles` · `numeric` in `weekly_checkins` | onboarding's free-text answer and the check-in's number share a name |
| `difficulty` | `integer` (1–5) in `workout_feedback` · `text` in `custom_exercises`, `workout_programs`, `workouts` | |
| `created_by` | **`text`** in `action_items` · `uuid` in `decision_traces`, `exercise_content_versions`, `program_versions` | `action_items.created_by` cannot FK to a user |
| `end_date` | `date` in `challenges`, `cycle_logs` · `timestamptz` in `events` | |
| `content` | `text` in 4 tables · `jsonb` in `exercise_content_versions` | |
| `ref_id` | `text` in `score_events` · `uuid` in `movement_nodes` | deliberate — `score_events.ref_id` is polymorphic |
| `value` | `numeric` in `habit_logs` · `text` in `platform_settings` | deliberate |
**Evidence:** DERIVED from the live column census.
**Data-integrity impact:** the first two are real: a `text` id cannot be constrained, so `workout_set_logs.exercise_id` can hold anything and no FK protects it. The rest are naming collisions rather than defects.
**Recommended fix:** convert `workout_set_logs.exercise_id` and `workout_sessions.workout_id` to `uuid` with FKs in a forward migration (after checking the stored values are UUID-shaped); rename `user_profiles.sleep_hours` → `sleep_hours_band` to end the collision.
**Product decision needed:** no. **Parallelizable:** yes.
**New in this workstream.**

---

#### I-TYP-02 · P2 · 92 enum-like text columns; 7 are constrained
**Evidence:** DERIVED — every `text` column whose name contains `status|type|kind|role|category|source|tier|mode|state|unit|level|goal|visibility`. Constrained: `user_profiles.{role, membership_tier, coaching_mode, unit_preference}`, `coach_availability.type`, `coaching_calls.call_type`, `custom_exercises.content_status`. Plus `workout_sessions.status` (`NOT VALID`).
**Concrete divergence found:** `workout_program_assignments.status` has **two terminal vocabularies for one state** — `coach_program_service.dart:264` writes `'replaced'`, `generate_client_plan()` (migration `121:206`) writes `'superseded'`. Both are currently harmless because every reader uses the positive filter `.eq('status','active')`; the first negative filter anyone writes will be wrong. `custom_exercises.submission_status` defaults to `NULL` while a reader filters `'pending'` (I-COM-03). `event_registrations.status` gains `'attended'` from `vendor_service.dart:51`, which no other site knows about.
**Recommended fix:** constrain the vocabularies that drive behaviour — `coach_client_relationships.status`, `workout_program_assignments.status`, `weekly_checkins.status`, `payments.status`, `subscriptions.status`, `class_bookings.status`, `custom_exercises.submission_status` — with `NOT VALID` CHECKs, and pick one spelling per state.
**Product decision needed:** no (each vocabulary is discoverable from the code).
**Parallelizable:** yes.

---

#### I-TYP-03 · P3 · 52 naive-local timestamps against 5 UTC-correct ones
`DateTime.now().toIso8601String()` (no timezone designator, local wall-clock) is written
into `timestamptz` columns at **52** sites; `toUtc().toIso8601String()` at **5**. This is
**RC-8**, already named in the master reconciliation and already fixed for exactly one
column by migration `108`. Re-verified unchanged; not re-argued here. Its interaction with
this report: every day-boundary query in nutrition, check-in and scoring
(`gte(start).lt(end)` built from local midnight) inherits it.
**Cross-ref:** RC-8, CON-06, CON-07.

---

## 5. Contract matrix

Legend: **W** writer · **R** reader · ✅ agrees with the live schema · ❌ names something that does not exist · ⚠️ exists but the two sides disagree.

### 5.1 Check-in — `weekly_checkins`

| Party | Columns touched | Verdict |
|---|---|---|
| W `submitWeeklyCheckin()` | `mood, energy, stress_level, sleep_hours_avg, notes, overall_score, submitted_at, status, week_number, week_start_date` | ✅ |
| W seed `test_accounts.sql` | `coach_id, weight_kg, energy_level, stress_level, sleep_hours, hunger_level, compliance_percent, notes` | ⚠️ **disjoint from the app writer** (I-CHK-04) |
| W `submitCoachFeedback()` | `status, feedback_message, feedback_recommendations, coach_name, reviewed_at` | ✅ (allowed by `enforce_checkin_authorship`) |
| R `_fromRow()` | `mood, energy, stress_level, sleep_hours_avg, notes, status, feedback_*` | ✅ |
| R `getSubmittedCheckinsForCoach()` | `status='submitted'` | ⚠️ seed rows are `'pending'` |
| R `insights_provider` | `energy_level, sleep_hours, weight_kg, stress_level` | ⚠️ 3 of 4 null (I-CHK-03) |
| R `trg_notify_coach_on_checkin` | `coach_id, weight_kg, energy_level, compliance_percent, week_number` | ❌ unreachable (I-CHK-02) |
| R `ai_adjust_nutrition` | `weight_kg` | ❌ no writer (I-NUT-02) |
| W/R `checkin_service.dart` | table `checkins` | ❌ **no such relation** (I-CHK-01) |

### 5.2 Nutrition

| Party | Object | Verdict |
|---|---|---|
| W `logMeal()` | `nutrition_logs(calories, protein, carbs, fat, amount_g, serving_unit, logged_at)` | ✅ |
| R `getTodayTotals()` | `protein, carbs, fat` | ✅ |
| R `ai-coaching-engine` | `protein_g, carbs_g, fat_g` | ❌ 400 (I-NUT-01) |
| W coach `assignNutritionPlan()` | `client_nutrition_plans(*)` deactivate+insert | ⚠️ non-atomic (I-NUT-04) |
| W `ai_adjust_nutrition()` | in-place `UPDATE` of the coach's row | ⚠️ destroys attribution (I-NUT-03) |
| R × 4 | `.eq('is_active',true).maybeSingle()` | ⚠️ 406 on a second active row (I-NUT-04) |

### 5.3 Intelligence

| Party | Object | Verdict |
|---|---|---|
| R `ai-coaching-engine:123` | `user_profiles.goal` | ❌ 400 — whole profile lost (I-INT-01) |
| R `ai-generate-workout:63` | `user_profiles.goal, equipment` | ❌ 400 — **injury data lost** (I-INT-02) |
| R `ai-generate-workout:66` | `custom_exercises` where `visibility='global' AND submission_status='approved'` | ⚠️ ungated (I-COM-03) |
| W engine | `ai_insights.type ∈ {daily_insight, accountability, risk, progress, meal_suggestion}` | ⚠️ 3 unread (I-INT-03) |
| W/R RPCs | 47 client `.rpc()` calls | ✅ params and returns (§3.5) |

### 5.4 Payments

| Party | Object | Verdict |
|---|---|---|
| W webhook | `subscriptions` upsert on `stripe_subscription_id` | ✅ |
| W webhook | `payments` update by id | ✅ idempotent |
| W webhook | `coach_client_relationships` upsert on the pair | ✅ |
| W webhook | `event_registrations` upsert on `(event_id,user_id)` | ✅ |
| W webhook | `client_session_credits` **plain insert** | ❌ duplicates on retry (I-PAY-01) |
| R client | `status ∈ {active, trialing}`, `payments.status='paid'` | ⚠️ unconstrained vocabulary (I-PAY-02) |

### 5.5 Notifications / messaging

| Party | Object | Verdict |
|---|---|---|
| W `sendMessage()` text | `messages(conversation_id, sender_id, content, is_read, sent_at)` | ✅ |
| W `sendMessage()` image | `messages.metadata` | ❌ no such column (I-NOT-01) |
| W `getOrCreate*Conversation()` | `conversations` check-then-insert | ⚠️ no unique pair (I-NOT-05) |
| W `markAsRead()` | `messages.is_read` | ⚠️ policy permits any column (I-NOT-04) |
| W community/class | `notifications` insert | ❌ rejected by `may_notify()` (I-NOT-02) |
| W triggers × 2 | `notifications` on session completion | ⚠️ duplicated (I-NOT-03) |

### 5.6 Community / events

| Party | Object | Verdict |
|---|---|---|
| W/R event ticket | `event_registrations.ticket_code` | ❌ column is `qr_code`; fabricated fallback (I-COM-01/02) |
| W `submitForGlobalLibrary()` | `submission_status='approved'` directly | ⚠️ bypasses moderation (I-COM-03) |
| W `approveGlobalExercise()` | `custom_exercises.approved_by` | ❌ column is `last_reviewed_by` (I-COM-03) |
| R `getPendingGlobalSubmissions()` | `submission_status='pending'` | ⚠️ nothing writes it (I-COM-03) |
| W/R class booking | `class_bookings`, `classes.current_enrolled` | ❌ RLS-scoped reads treated as global (I-COM-04) |

### 5.7 Workout intersections

| Party | Object | Verdict |
|---|---|---|
| W `recordSet()` | `workout_set_logs(session_id, set_id, user_id, …)` | ✅ satisfies `require_identity` + `protect_history` |
| R `getExerciseProgression()` | `workout_set_logs.created_at` | ❌ column is `logged_at` (I-WRK-01) |
| R `trg_detect_pr` | `AFTER INSERT` only | ⚠️ misses the update path (I-WRK-02) |
| W `logWorkout()` + session complete | `workout_logs` **and** `workout_sessions` | ⚠️ dual non-atomic write (I-LEG-01) |
| — | `workout_sessions.program_workout_id` | ⚠️ no writer (I-WRK-03) |
| W/R program_workouts | canonical `exercises` jsonb | ✅ trigger + `NOT VALID` CHECK (119) |

---

## 6. Root-cause clusters

Forty-three findings collapse into nine causes. Five are already named in the master
reconciliation; four are new to this workstream.

| ID | Cause | Findings |
|---|---|---|
| **RC-5** *(existing)* | The same domain concept modelled twice and never reconciled | I-CHK-03, I-NUT-02, I-USR-03, I-LEG-01, I-INT-01, I-INT-02, I-TYP-01 |
| **RC-7** *(existing)* | Errors caught and returned as a valid empty value | I-CHK-01, I-NUT-01, I-INT-01, I-INT-02, I-COM-01, I-COM-02, I-WRK-01, I-LEG-03, I-NOT-01, I-NOT-02 |
| **RC-8** *(existing)* | Naive local time written into `timestamptz` | I-TYP-03 |
| **RC-3** *(existing)* | A security property enforced by a sweep rather than at the point of definition | I-MIG-03 |
| **RC-4** *(existing)* | Server-side logic trusting a parameter/column instead of deriving it | I-CHK-02 |
| **RC-9** *(new)* | **A `catch` that manufactures a plausible success.** Distinct from RC-7: RC-7 returns emptiness, RC-9 returns *fiction*. | **I-COM-01** ("Demo fallback" issues a ticket code for a row that was never written) |
| **RC-10** *(new)* | **An identity model that lives in application convention instead of in an index.** Every instance is a missing UNIQUE plus a check-then-insert. | I-NUT-04, I-NOT-05, I-COM-06, I-WMH-01, I-PAY-01 |
| **RC-11** *(new)* | **Aggregate or cross-user operations written as client-side queries against per-user RLS.** The query is not denied, it is *scoped* — and a silently narrowed result is indistinguishable from a real one. | **I-COM-04** (capacity, waitlist, enrolment) |
| **RC-12** *(new)* | **Fixtures written against readers rather than against the writer**, so QA exercises a contract the application does not use. | **I-CHK-04** |

RC-9 and RC-11 deserve a repo-wide sweep of their own. RC-9 because a fabricated success
is worse than a failure and there may be more "Demo fallback" blocks. RC-11 because
PostgREST returns HTTP 200 for an `UPDATE` that matched zero rows, so this class produces
no error anywhere — not in a log, not in a `catch`, not in a test.

**The mechanical enabler behind RC-7 is worth stating once.** PostgREST validates the
select list before it evaluates authorization, so a bad column name yields
`400 / 42703`, not a permission error — verified live (§11.2). Combined with 49
error-swallowing `catch` blocks in `apps/mobile/lib`, a typo in a column name is
functionally identical to a feature that was never built. Eleven such references are open.
`npm run test:contract` now makes the tenth impossible.

---

## 7. Migration hazards

### 7.1 Remote history divergence — **the one to fix first**
Migrations **113–122** are applied to QA and **not recorded** (I-MIG-01). Consequence:
`supabase db push` re-runs all ten. Everything else in this section exists because of that.

### 7.2 Idempotency of 113–122 — verified safe · SRC
Each was read for statements that are not safely repeatable:

| Migration | Non-idempotent shape? | Verdict |
|---|---|---|
| 113, 114, 117, 118 | `CREATE POLICY` | preceded by `DROP POLICY IF EXISTS`; safe |
| 115 | `ADD CONSTRAINT user_profiles_role_check` | preceded by `DROP CONSTRAINT IF EXISTS`, and by a `DO` block that **raises** if any existing row holds an unknown role rather than silently dropping the check; safe and well-built |
| 116, 121, 122 | `INSERT INTO …` | all inside **function bodies**, not top-level; safe |
| 119 | `ADD CONSTRAINT program_workouts_exercises_canonical` | `DROP … IF EXISTS` first, added `NOT VALID`; safe |
| 120 | `ADD CONSTRAINT workout_sessions_status_known`, `CREATE INDEX` | `DROP … IF EXISTS` / `IF NOT EXISTS`; safe |

**All ten are idempotent.** A `db push` today would be a no-op in effect. That is a
property of how they were written, not of the process — I-MIG-01 still needs fixing.

### 7.3 `CREATE OR REPLACE` drift — I-MIG-03
The `search_path` pin is a per-definition property that `119`/`120` omit and `122`
restores. Correct today only because `122` sorts last. A standing test is the fix, not a
second sweep.

### 7.4 `NOT VALID` constraints and an unread warning — I-MIG-02
Both `ALTER`-added CHECKs are `NOT VALID` by design. Migration `119` emits a `RAISE
WARNING` naming un-canonicalisable `program_workouts` rows; there is no record that the
query it suggests was ever run.

### 7.5 Backfill correctness · SRC
Reviewed: `062` (`submission_status` backfill for `visibility='global'` rows), `071`
(exercise slugs), `108` (`started_at` authority), `111` (replay corrections), `119`
(prescription canonicalisation), `121` (self-generated plan day titles). All are guarded
(`WHERE … IS DISTINCT FROM`, `coach_id IS NULL` scoping so a coach's titles are never
rewritten) and all are re-runnable. **No backfill defect found.** `119`'s residue is the
only open item (§7.4).

### 7.6 Ordering hazards · SRC
Filename-ordered application is the only ordering, and it is consistent. Two ordering
dependencies are real but currently satisfied: `122` must sort after `119`/`120`
(§7.3), and `115`'s role CHECK must sort after every migration that writes a role.
The `db.seed` block in `supabase/config.toml` explicitly lists its two files rather than
globbing, with a comment explaining that order matters — good practice, already applied.

---

## 8. Data-integrity risks

Ranked by what can silently corrupt or fabricate user data.

| # | Risk | Finding | Mechanism |
|---|---|---|---|
| 1 | A user is shown a ticket for an event they are not registered for | I-COM-01 | `catch` fabricates a code; no row exists |
| 2 | AI prescribes movement without knowing the user's injuries | I-INT-02 | two bad columns fail a query that also carried `has_injuries` |
| 3 | A coach's nutrition prescription is overwritten and misattributed | I-NUT-03 | in-place `UPDATE`, `coach_id` unchanged, `notes` destroyed |
| 4 | A client is granted session credits they did not pay for | I-PAY-01 | non-idempotent insert on an at-least-once webhook |
| 5 | A participant rewrites the other person's message | I-NOT-04 | UPDATE policy with no `WITH CHECK` and no column restriction |
| 6 | User-authored image messages are destroyed | I-NOT-01 | unknown column → 400 → `return false` |
| 7 | A client silently eats to default macros instead of their plan | I-NUT-04 | two active rows → `maybeSingle()` 406 → fallback |
| 8 | Cycle-phase guidance computed from duplicated/never-closed periods | I-WMH-01 | no unique, no ordering CHECK |
| 9 | Classes overbook past capacity; a freed seat is never offered | I-COM-04 | RLS-scoped counts read as global; 0-row UPDATE returns 200 |
| 10 | Unreviewed exercise content reaches every user | I-COM-03 | publish path writes `'approved'` itself |
| 11 | Streak/completion disagree between two tables | I-LEG-01 | dual non-atomic write, disjoint readers |
| 12 | QA reports check-in as working when it is not | I-CHK-04 | fixtures write the opposite column family |

Risks 1–5 can put wrong data in front of a user or in the database. Risks 6–12 lose or
distort data without corrupting it.

---

## 9. Product decisions required

**None of these is decided here.** Each blocks a fix.

| # | Question | Blocks | Where it comes from |
|---|---|---|---|
| **Q-1** | Is there a **daily** check-in distinct from the weekly one? | I-CHK-01 | Open since Phase 0; the `weekly_checkins` table comment records that weekly behaviour is to be derived from daily data "in a later phase" that has no schema |
| **Q-2** | Which `weekly_checkins` column family is canonical, and are `hunger_level`/`compliance_percent` part of the form? | I-CHK-02/03/04, I-NUT-02 | I-CHK-03 |
| **Q-3** | Is body weight captured by the check-in or by `weight_logs`? Both model it. | I-NUT-02 | I-NUT-02 |
| **Q-4** | May the engine change a **coach-assigned** nutrition plan, or only a self-generated one? | I-NUT-03 | I-NUT-03 |
| **Q-5** | Should AI workout generation **fail closed** when safety inputs are unavailable? | I-INT-02 | I-INT-02 |
| **Q-6** | Which of the five duplicated `user_profiles` concepts is authoritative? | I-USR-03, I-INT-01/02, I-NUT-02 | I-USR-03 |
| **Q-7** | Is program deletion *archive* or *erase*? | I-USR-01, I-WRK-03 | I-USR-01 |
| **Q-8** | What is the account-deletion contract the Help Center already promises? | I-USR-01 | `help_center_screen.dart:45` |
| **Q-9** | Is global exercise publishing moderated? The migrations say yes; the app says no. | I-COM-03 | `050:3` vs `submitForGlobalLibrary()` |
| **Q-10** | May a sender edit or delete their own message after sending? | I-NOT-04 | I-NOT-04 |
| **Q-11** | Is `workout_sessions` canonical, and must pre-`035` `workout_logs` history be preserved? | I-LEG-01 | I-LEG-01 |
| **Q-12** | Are risk/progress insights a shipped feature? Do `exercise_analytics` and `score_cycles` have a consumer coming? Is "coach tips" a feature? | I-INT-03, I-LEG-02, I-LEG-03 | dead-object census |

---

## 10. Remediation dependencies

```
I-MIG-01 (repair remote migration history)
   └── everything below, because every forward migration ships through it

Independent — no dependency, no decision, mechanical:
   I-NUT-01  nutrition_logs.protein_g → protein          (Edge Function, 1 line)
   I-INT-01  user_profiles.goal → fitness_goal           (Edge Function, 1 line)
   I-WRK-01  workout_set_logs.created_at → logged_at     (Dart, 2 sites)
   I-COM-02  event_registrations.ticket_code → qr_code   (Dart, 1 site)
   I-NOT-01  ADD COLUMN messages.metadata jsonb          (forward migration)
   I-NOT-02  extend may_notify()                         (forward migration)
   I-NOT-03  drop the duplicate completion trigger       (forward migration)
   I-WRK-02  trg_detect_pr → AFTER INSERT OR UPDATE      (forward migration)
   I-PAY-01  UNIQUE (payment_id) + upsert                (forward migration + Edge Function)
   I-NUT-04  partial UNIQUE on the active plan + atomic RPC
   I-WMH-01  UNIQUE + CHECK on cycle_logs
   I-NOT-05  UNIQUE on the conversation pair + one RPC
   I-COM-04  book/cancel RPC + enrolment trigger
   I-USR-02  auth.users email write-through trigger
   I-MIG-03  standing search_path test

Decision-gated:
   Q-5  → I-INT-02  (fail closed?)      ── highest severity; the column fix is 1 line,
                                            the fail-closed behaviour is the decision
   Q-9  → I-COM-03  (moderated?)        ── (a) approved_by→last_reviewed_by can land now;
                                            (b)+(c) must land together
   Q-1  → I-CHK-01
   Q-2  → I-CHK-02 → I-CHK-04
   Q-2+Q-3 → I-NUT-02 → I-NUT-03 (same function, one rewrite)
   Q-6  → I-USR-03  (and cleanly closes I-INT-01/02's root cause)
   Q-7  → I-USR-01(a) → I-WRK-03
   Q-8  → I-USR-01(b)
   Q-10 → I-NOT-04
   Q-11 → I-LEG-01  (six readers move together)
   Q-12 → I-INT-03, I-LEG-02, I-LEG-03

Ordering note:
   I-WRK-03 (populate program_workout_id) MUST NOT land before Q-7 is answered.
   The FK is NO ACTION; populating the column makes generate_client_plan()'s delete
   of self-generated programs start failing with 23503 for any client who has trained.
```

**Suggested first slice** — no decisions, no schema risk, closes four P0/P1s and one P0
root cause: I-MIG-01, then the five one-line column renames (I-NUT-01, I-INT-01,
I-INT-02's column half, I-WRK-01, I-COM-01/02), then `npm run test:contract` and remove
the corresponding entries from `known-violations.json`. The guard will fail if an entry
is removed without the fix, or fixed without the removal.

---

## 11. Test results

### 11.1 Existing suites — all green, nothing weakened

| Suite | Command | Result |
|---|---|---|
| Flutter | `cd apps/mobile && flutter test` | **730 passed, 9 skipped, 0 failed** |
| API unit | `npm test --workspace apps/api` | **58 passed, 8 suites** |
| API e2e | `npm run test:e2e --workspace apps/api` | **6 passed, 2 suites** |
| Contract *(new)* | `npm run test:contract` | **PASS** |

Run before and after this workstream's changes; identical results. **No existing test was
modified, skipped, relaxed or deleted.**

`npm run test:security` was **not run**: it requires `QA_SERVICE` (the QA service-role
key), which was not available to this session, and it performs live write probes. Its
subject matter (Phase 1 posture) was instead verified read-only in §3.4.

### 11.2 Live probes (2, both read-only, both `GET`)

```
GET /rest/v1/nutrition_logs?select=calories,protein_g&limit=1   [anon key]
→ 400 {"code":"42703","hint":"Perhaps you meant to reference the column
       \"nutrition_logs.protein\"","message":"column nutrition_logs.protein_g does not exist"}

GET /rest/v1/nutrition_logs?select=calories&limit=1             [anon key]
→ 401 {"code":"42501","message":"permission denied for table nutrition_logs"}
```

Two facts established, both load-bearing for this report: an unknown column yields
`400 / 42703`, and **PostgREST parses the select list before it checks authorization** —
so the 400 reaches an authenticated caller identically. This is why every "column does not
exist" finding is a hard failure rather than a partial result, and why they are invisible.

### 11.3 New test — schema contract guard

Added: `supabase/tests/contract/{run.mjs, schema.mjs, known-violations.json, README.md}`
and one line in `package.json` (`"test:contract"`).

**Why it was needed.** The finding class in §6 RC-7 is the largest in this report, is
invisible to all 794 existing tests, and recurs on any typo. `schema.mjs` replays the
migrations offline and reconstructs the schema; `run.mjs` asserts every `.from()`,
`.select()` and write-payload key against it. Embedded resources, storage buckets and
keys nested inside `jsonb` values are correctly excluded.

**Contacts no environment.** The schema model was verified byte-exact against the live QA
dump before being relied on (§3.2).

**It is a characterization test, not an aspiration.** `known-violations.json` records the
ten open violations, each tagged with its finding ID, and is checked **in both
directions**: an unlisted violation fails (a new defect), and a listed entry that no
longer reproduces also fails (a stale excuse). The list can only shrink.

**Proven to have teeth.** A probe file referencing `table_that_does_not_exist` and
`user_profiles.not_a_real_column` was added, the guard failed with both, and the probe was
deleted; the guard returned to PASS. See §13.

```
Schema contract guard — 91 tables + 5 views derived from supabase/migrations

  known  relation checkins                          I-CHK-01  (7 sites)
  known  relation coach_tips                        I-LEG-03  (1 site)
  known  column   event_registrations.ticket_code   I-COM-01  (3 sites)
  known  column   custom_exercises.approved_by      I-COM-03  (1 site)
  known  column   workout_set_logs.created_at       I-WRK-01  (1 site)
  known  column   user_profiles.goal                I-INT-01  (2 sites)
  known  column   nutrition_logs.protein_g          I-NUT-01  (1 site)
  known  column   nutrition_logs.carbs_g            I-NUT-01  (1 site)
  known  column   nutrition_logs.fat_g              I-NUT-01  (1 site)
  known  column   user_profiles.equipment           I-INT-02  (1 site)

PASS  no unknown relation or column outside the 10-entry known-violations allowlist
```

**Declared blind spot**, stated in the README so it is not mistaken for coverage: a
payload key assigned dynamically (`row['metadata'] = value`) rather than written as an
object literal is invisible to the guard. **I-NOT-01 is exactly that shape** and is
deliberately *not* allowlisted, because the guard can neither prove nor disprove it.

### 11.4 Analysis scripts (scratch, not committed)

Migration-vs-live column parity; the `.select()` column checker; the write-payload key
checker; the RPC parameter/return checker; the enum-vocabulary extractor; the
writer/reader census for dead objects; the same-name-different-type census. Each produced
a table quoted above. They were run from the session scratchpad and are **not** added to
the repository — only the guard in §11.3, which is the durable part, is.

---

## 12. Current working-tree changes observed

Recorded, not judged, and **nothing was reverted, stashed or overwritten**.

* **100 entries** in `git status` at session start; **113** at the end (this workstream
  added 4 files and modified `package.json`; a concurrent workstream added
  `supabase/tests/ai/` and a `test:ai` script during the session).
* **15 historical migrations are modified in the working tree** — `001, 002, 003, 009,
  076, 080, 083, 084, 086, 087, 090, 091, 096, 097, 102` (+338/−81 lines). Sampling them,
  these are **replay-repair edits**, tagged in-file with `STAGE A.6` / `STAGE B.2`–`B.4`
  markers and explanatory comments. `001`'s edit, for example, adds
  `SET search_path = public, extensions;` because the file declares defaults using an
  unqualified `gen_random_bytes()`, which does not resolve under the role
  `supabase db reset` uses.
  **Assessment:** the audit brief says not to modify historical migrations, and this
  report modifies none. These pre-existing edits are noted as a hazard rather than a
  defect: the parity proof in §3.2 holds for the **working tree**, and QA was rebuilt from
  exactly these files. Production was built from the **committed** versions, which differ.
  Anything inferred about production from this tree is therefore unsound, which is one
  more reason I-MIG-01 matters.
* **20 untracked migrations** — `000_baseline_preexisting_tables.sql` and `104`–`122`.
  `000` is what makes `db reset` reproduce the pre-existing tables; without it the tree
  does not describe the database. **They should be committed.** They are load-bearing:
  113–118 are the Phase 1 security migrations.
* **13 untracked docs** — every prior workstream report.
* **~22 modified/untracked Dart files** concentrated in the workout domain (Phase 2
  remediation: `workout_contract.dart`, `workout_restoration.dart`, and 12 new test files).
* `supabase/.temp/*` and `supabase/config.toml` modified — CLI link state for the QA
  project, plus the explicit `db.seed.sql_paths` block.
* **Concurrent activity:** `package.json` changed underneath this session (a `test:ai`
  script and `supabase/tests/ai/` appeared). This workstream's edit to `package.json` was
  applied as a single additive line anchored on the existing content, not as an
  overwrite, and both scripts are present afterwards.

---

## 13. QA mutation and cleanup

**No row in QA was created, updated or deleted. No schema object was created, altered or
dropped. No migration was applied, repaired or rolled back.**

Operations performed against QA, exhaustively:

| Operation | Type |
|---|---|
| `supabase db dump --linked --schema public -f <scratchpad>` | read-only; output written to the session scratchpad, never to the repository |
| `supabase migration list --linked` | read-only |
| 2 × `GET /rest/v1/nutrition_logs?select=…` with the **anon** key (§11.2) | read-only; both returned errors, no rows |

The service-role key was never held by this session. **No write probe was issued**, which
is why I-MIG-02's repair query (§7.4) is a recommendation rather than a result.

Local working-tree mutations, all intentional and all accounted for:

| Path | Action |
|---|---|
| `supabase/tests/contract/run.mjs` | **added** |
| `supabase/tests/contract/schema.mjs` | **added** |
| `supabase/tests/contract/known-violations.json` | **added** |
| `supabase/tests/contract/README.md` | **added** |
| `package.json` | **one line added** — `"test:contract"`; no existing line altered |
| `docs/QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md` | **added** (this file) |
| `apps/mobile/lib/__contract_guard_probe.dart` | **created and deleted** — the guard self-test in §11.3. Verified gone: absent from `git status`, and the guard returned to PASS afterwards. |

No existing file was reverted, stashed, discarded or overwritten. No existing test was
weakened. Migrations 113–121 were not touched.

---

## 14. Production-contact statement

**Production (`nxdbooufqzkpslkcogxc`) was not contacted in any form during this
workstream** — no connection, no dump, no REST request, no CLI command, no read, no write.

The Supabase CLI in this tree is linked to **QA (`eyqtldjqpgpljlqvpowh`)**, confirmed
against `supabase/.temp/project-ref` and against `SUPABASE_URL` in
`apps/mobile/dart_defines/qa.json`. The production reference appears exactly once in the
tree, as `_prodSupabaseUrl` in
[`app_env.dart:117`](../apps/mobile/lib/core/config/app_env.dart#L117), and was read only
to establish that the linked project is **not** it.

**No claim in this report describes production.** Every LIVE result is a QA result.
Because 15 historical migrations are modified in the working tree (§12) and because QA's
migration history does not record 113–122 (I-MIG-01), **the deployed state of production
cannot be inferred from this repository**, and this report does not attempt to. The
source-level findings — every missing column, every missing writer, every unconstrained
vocabulary — are properties of the code and the migrations, and so apply wherever that
code runs. The schema-level confirmations in §3.2–§3.4 apply to QA only.
