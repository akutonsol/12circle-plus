# F-21 — screen-level blast radius

**Status: OPEN. P1. Remediation is owner-controlled (OD-14) and has not been attempted.**
Static analysis only. No policy was changed and no further live mutation was performed —
the standing instruction is not to exercise a vulnerable authorization path beyond the one
probe that established the finding.

---

## 1 · The defect, restated precisely

```sql
CREATE POLICY "coaches manage programs" ON workout_programs
  FOR ALL TO authenticated USING (coach_id = auth.uid());
```

The policy is *named* for coaches and never checks that the caller is one. Two properties
combine:

1. **`FOR ALL` with no `WITH CHECK`.** PostgreSQL applies the `USING` expression to
   `INSERT` as well, so the row the caller is writing only has to satisfy it — and the
   caller controls `coach_id`.
2. **The predicate is a column the caller writes.** "Am I allowed to do this?" is answered
   with "yes, because I said so."

`public.is_coach_profile(uuid)` already exists (`113_rls_coach_client_relationships.sql:58`)
and migration 113 applies exactly that check to `coach_client_relationships`. It was never
applied to these fifteen tables.

**Proven, once, against QA** (rows deleted, cleanup verified — see `QA_EVIDENCE.md` F-21):
a client-role fixture created a programme naming itself coach (201), and then assigned it
to **another user** (201).

---

## 2 · The population, split by severity

The fifteen policies are **not** equally dangerous. The split is whether the predicate
names one party or two.

### 2a · Two-party — **cross-user write** (5 policies, 4 tables)

`USING (coach_id = auth.uid() OR client_id = auth.uid())`

Either disjunct satisfies the policy, so a caller can write a row naming **itself as coach
and any other user as client**. This is the class that reaches a victim.

| Table | Policy |
|---|---|
| `workout_program_assignments` | "coaches manage assignments" — **the proven one** |
| `client_nutrition_plans` | "coach client nutrition" |
| `client_habits` | "coach client habits" |
| `coaching_calls` | "Coach and client can see calls" (`002`) |
| `coaching_calls` | "calls_participant_access" — **a second one on the same table**, so a correction has to find both |

### 2b · Single-party — **self-forgery** (11 tables)

`USING (coach_id = auth.uid())`

The caller can create rows that claim they are a coach, but cannot attach another user to
them directly. The damage is to data integrity and to any surface that treats "has rows
here" as "is a coach".

`coach_invites`, `workout_programs`, `program_workouts`¹, `challenges`, `classes`,
`coach_availability`, `accountability_pods`, `coach_team_members`, `coach_team_invites`,
`custom_exercises`, `action_items`.

¹ `program_workouts` guards by subquery — `program_id IN (SELECT id FROM workout_programs
WHERE coach_id = auth.uid())` — which is only as strong as `workout_programs`. An attacker
who owns a forged programme owns its workouts too. It is **single-party by shape and
chained in practice**.

---

## 3 · What a victim would actually see

### 3a · `/train` and `/active-workout` — a forged programme, startable

The chain is static-provable end to end:

| Step | Code |
|---|---|
| read | `CoachProgramService.getMyAssignedProgram()` — `coach_program_service.dart:219` |
| filter | `.eq('client_id', me).eq('status', 'active').maybeSingle()` |
| decode | `assignedWorkoutsProvider` — `workout_provider.dart:194` |
| surface | `/train` hub (FIT-014/015), `getTodaysWorkout()` → `/home`, and `/active-workout` |

A forged assignment row satisfies that filter exactly as a real one does. **The victim sees
prescribed exercises, loads and rep schemes attributed to their coach, and can start and
log the session.** In a strength product that is a physical-safety exposure, not only a
data-integrity one: the attacker chooses the weights.

**A second effect, not previously recorded.** The read uses `.maybeSingle()`. A victim who
already has a real active assignment and receives a forged one now matches **two** rows, and
`maybeSingle()` fails. The forged row does not merely add a fake programme — **it makes the
victim's real programme unreadable**. Since `assignedWorkoutsProvider` now propagates its
errors (F-15 work), that surfaces as `_PlanUnavailable` rather than as an empty plan, so the
client is at least told the plan could not be loaded rather than told they have none. The
denial stands either way.

### 3b · `/home` and `/checkins` — forged coaching calls

`coaching_calls` is two-party. A forged row with `client_id = victim`:

| Surface | Read | Effect |
|---|---|---|
| `/checkins` | `checkin_screen.dart:118` — `.eq('client_id', me).eq('status','scheduled')` | a session the victim never booked appears in "upcoming" |
| `/home` | `weeklyActivityProvider` — `home_screen.dart:67`, `.eq('client_id', me)` | **inflates the victim's activity bars**; calls are weighted ×3 in that calculation |
| `/booking` | `booking_screen.dart:185` | appears in the victim's bookings with that coach |

### 3c · Nutrition and habits

`client_nutrition_plans` and `client_habits` are two-party. Forged rows land under the
victim's `client_id` and are read by `coach_program_service.dart:291/301` and
`coach_ecosystem_provider.dart:183`. Impact is prescription-shaped, like 3a: a nutrition
target or habit the victim's coach never set.

### 3d · Self-forgery surfaces (2b)

No victim, but a forged `classes` or `challenges` row is **visible to everyone** — those
tables have separate public read policies — so a non-coach can publish a class or a
challenge into the product's shared surfaces. `/classes` (FIT-027) and `/challenges`
render them as real.

---

## 4 · Which screens are safe to keep integrating

The distinction that matters is **whether the screen's correctness depends on the integrity
of a row written through one of these policies.**

### BLOCKED-BY-F21 — do not claim integrity closure on these

| Screen | Why |
|---|---|
| `/train` · FIT-014, FIT-015 | renders the assigned programme (3a) |
| `/active-workout` · FIT-002, FIT-016, FIT-017, FIT-018 | executes it |
| `/checkins` · FIT-023 | upcoming coaching calls (3b) |
| `/booking` | the same calls |
| nutrition plan surfaces · FIT-003 | 3c |
| habits surfaces | 3c |
| `/coach-dashboard` · FIT-032 | writes through these policies as its normal path |

**This does not mean they cannot be worked on.** FIT-002 was taken to 5/5 while F-21 was
open, because its work was accessibility and interaction, not data trust. The rule is
narrower: *do not assert that what these screens display is authentic*, and do not build a
feature whose safety argument rests on one of these rows being written by a coach.

### Safe to integrate — no dependency on a vulnerable row

`/messages` · FIT-005, FIT-028 · `/classes` structure · `/home`'s week card ·
`/daily-checkin` · `/profile` · `/progress` · `/intake` · auth.

`/classes` needs a distinction: the **screen structure** (FIT-027) is safe, and it is what
was built. The **content** can include a forged class (3d), which is a data-authenticity
problem in the rows, not in the screen.

---

## 5 · What is holding the line while the decision is outstanding

| Guard | Holds |
|---|---|
| **SEC-G1** | the full population at 15. A sixteenth policy of this shape fails the build. |
| **SEC-G2** | the two-party subset at **5 policies across 4 tables** — the cross-user-write class specifically, so a new one cannot hide inside SEC-G1's larger number by displacing a single-party policy and leaving the total unchanged. |

Both were mutation-tested: a sixth two-party policy fails SEC-G2 (`Found 6`), and a
sixteenth single-party one fails SEC-G1 (`Found 16`) without disturbing SEC-G2.

**A correction of record.** This analysis first said `coaching_calls` carried its policy
"×2 — `002` defines it twice", from reading the migration. SEC-G2 measured it and the two
are different policies with different names, one of them added later. The count is five,
not four. Guessing at a duplicate and measuring one are not the same thing, and only the
second would have caught a correction that fixed one and left the other.

Both parse the real `supabase/migrations/*.sql`. Neither changes a policy. Both are
ratchets: lower them when policies are corrected, never raise them.

---

## 6 · The decision that is actually needed — OD-14

Not "should this be fixed" — it plainly should. The decision is **what the correct
authorization model is**, and that is a product question this analysis cannot answer:

1. **Who may create a programme?** Any user with a coach profile, or only a coach with an
   active relationship to the client being assigned?
2. **Is `is_coach_profile(coach_id)` sufficient**, or must the assignment also require an
   active `coach_client_relationships` row between the two parties? Migration 113 already
   implies the second for relationships themselves.
3. **What happens to existing rows** that would not satisfy the corrected policy? There may
   be legitimate production data written before any of this was tightened.

The mechanism is free — migration 113 supplies both the helper and the pattern. The policy
is a decision about the product's relationship model, which is why it has not been changed
autonomously.
