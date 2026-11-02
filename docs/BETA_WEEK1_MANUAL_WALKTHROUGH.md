# Beta week 1, manual route: QA walkthrough

**What this proves:** the first-beta loop (a coach builds week 1 by hand, assigns
it, the client trains it, the coach sees it) works on the **real QA project**
as it is today (migrations 000-181).

**Why it is possible now:** the hand-built route stores exercises as typed names
and reads nothing from the exercise library, so it needs no certified content,
no `exercise_intelligence` rows and none of migrations 182-195. The engine route
("Generate week 1") stays off (`ENGINE_WEEK_GENERATION`) until those land.

**Already proven locally:** `supabase/tests/local/beta_manual_loop_replay.sh`
runs the app's exact reads and writes for this loop on a scratch replay. 23/23
pass on 000-181, 000-186 and 000-195. This walkthrough is the confirmation on QA
itself, through the real UI.

**What this does not prove:** the engine route, production, or anything on a
physical device unless you run it on one.

---

## Before you start

- [ ] A QA build of the app: `cd apps/mobile && flutter run --dart-define-from-file=dart_defines/qa.json`
      (or the web build from the same file). Never a production build.
- [ ] Two QA accounts you own: a **coach** and a **client**. Don't use the CI
      fixture identities, which the live suites own.
- [ ] Their coach-client relationship is **active**, not pending. Assigning to a
      client who hasn't accepted is refused once migration 185 is applied.
- [ ] Pick **today's weekday** for the training day. The client app shows a
      workout only when its day matches today.

## Steps (do → expect)

**Coach: build week 1**
1. [ ] Bottom bar → **Programs** → **New Program** → name it, set weeks → **Create & build**.
       → The program opens in the builder.
2. [ ] **Add Workout** → Week **1**, Day **(today)**, a title → **Add exercise** twice:
       - one with sets, reps, load and rest filled in;
       - one with **load and rest left blank**.
       → **Save workout**. The day shows both exercises. The blank load shows no
       weight; it must not show 0 kg.
3. [ ] (Optional) Add a second day later in the week.
       → Days are listed in week/day order.

**Coach: assign**
4. [ ] Bottom bar → **Clients** → open the client → **Assign / Change Program** →
       pick the program → **Assign Program**.
       → "Program assigned!" and the Overview tab shows it under **Assigned Program**.

**Client: see it and train it**
5. [ ] Sign in as the client. → A "New Workout Program" notification.
6. [ ] **Home** → the Today card names **your title** with "Assigned by …",
       the exercise count and minutes, and **Begin session**.
       → It must not say "Full Body Strength" or show a calorie figure.
7. [ ] **Workouts** tab → today's workout is the one you built, with both exercises.
8. [ ] Begin the session → log at least one set → finish.
       → The session completes with no error.
9. [ ] Home → Activity (if you open it) → its "Today's workout" card matches Home.
       *Known defect until `fix/activity-card-real-session` merges: this card
       shows "Full Body Strength · 45 min · ~380 kcal" for everyone. Note it but
       don't count it as a failure of this loop.*

**Coach: see the result**
10. [ ] Sign in as the coach → **Compliance** (or the client's **Progress** tab).
        → The completed session is there.

**Re-assign**
11. [ ] Assign a second program to the same client.
        → The client sees only the new one; the old one is no longer active.

## Record the result

For each step, record ✅ / ❌ / ⚠️, the platform (web / iOS / Android) and a
screenshot of any ❌. One ❌ in steps 1-8 or 10 means the beta can't start on
this route. Report it and it becomes the next fix.

Side effect: signing in this month also gives QA the authentication rows that
live check METRIC-02 needs. It fails on a new month until someone signs in.
