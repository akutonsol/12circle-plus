# Beta week 1, manual route: QA walkthrough

**What this proves:** the first-beta loop (a coach builds week 1 by hand, assigns
it, the client trains it, the coach sees it) works on the **real QA project**
through the real UI.

**This is the hand-built route, not the engine route.** The hand-built route
stores exercises as typed names and reads nothing from the exercise library, so
it needs no certified content, no `exercise_intelligence` rows and none of
migrations 182-195. The engine route ("Generate week 1") is a separate path. It
stays off (`ENGINE_WEEK_GENERATION`) until those land, and nothing here tests it.

**Already proven without QA:**
- `supabase/tests/local/beta_manual_loop_replay.sh` replays this loop's database
  reads and writes on a scratch database: 23/23 on migrations 000-181, 000-186
  and 000-195. It proves storage, permissions and isolation. It does not run the
  app, so it does not prove what a screen shows.
- `apps/mobile/test/unit/assigned_program_schedule_test.dart` proves that a saved
  training day gets the right calendar date and that Home picks it on that day.

This walkthrough is the confirmation on QA, on screen.

**What this does not prove:** the engine route, production, or anything on a
physical device unless you run it on one.

---

## How the app dates a training day

A training day says only "Week N, Day". The date comes from the day the program
was **assigned**: week 1 is the Monday-to-Sunday week that contains the
assignment date, week 2 is the week after, and so on. So:

- assigned on a Wednesday → week 1's Monday and Tuesday are already past, and
  week 1's Wednesday is today;
- assigned on a Sunday → week 1 is the week ending that Sunday, and week 2 starts
  the next day.

For this walkthrough, assign on the same day you test, and build the workout on
**Week 1, today's weekday**.

## Before you start

- [ ] A QA build from `main` that **includes the training-day dating fix**
      (`fix/hand-built-week-dates`). Without it, the Home Today card never shows
      a hand-built workout (step 6 fails). For step 8 it must also include the
      finished-day fix; without that, Home keeps offering the finished workout.
      `cd apps/mobile && flutter run --dart-define-from-file=dart_defines/qa.json`
      (or the web build from the same file). Never a production build.
- [ ] Two QA accounts you own: a **coach** and a **client**. Don't use the CI
      fixture identities, which the live suites own.
- [ ] Their coach-client relationship is **active**, not pending. Once migration
      185 is applied, assigning to a client who hasn't accepted is refused.
- [ ] The client is **Coach-Guided** and has no active self-generated plan. A
      client who onboarded as Self- or AI-Guided got a generated plan, and the
      coach's assign can't retire it, so the client would see "Couldn't load your
      plan". Switching the client to Coach-Guided in the app retires that plan;
      do that before step 4.
- [ ] **The client pays this coach.** The coach's Assign button appears only if
      the client has, with this coach, either
      - a subscription of kind `coach` or `package_monthly` with status `active`
        or `trialing`, or
      - a `package` payment with status `paid`.

      Without one, the client's page shows "Coaching services unlock once this
      client subscribes to one of your plans" and there is no Assign button. Set
      this up yourself, for example through the app's own checkout in Stripe test
      mode. Claude does not create subscriptions, payments or accounts.
- [ ] **Relaunch between roles (↻).** The app caches the coach's client page and
      the client's program, and neither signing out nor pulling down refreshes
      them. Before every step marked ↻, fully close and reopen the app (on web,
      reload the tab). Two devices or two browser profiles, one per role, avoid
      most of this. Stale screens without a relaunch are a known issue, tracked
      separately. Don't record them as failures of this loop.

## Steps (do → expect)

**Coach: build week 1**
1. [ ] Bottom bar → **Programs** → **New Program** → name it, set weeks → **Create & build**.
       → The program opens in the builder.
2. [ ] **Add Workout** → Week **1**, Day **(today)**, a title → under
       *Exercises* tap **Add** twice:
       - one exercise with sets, reps, load and rest filled in;
       - one with **load and rest blank**. Load starts empty. **Rest starts at 60,
         so delete it.** Sets (3) and reps (10) are required.

       → **Save workout**. The day lists both exercises. The blank one shows
       sets×reps only: no "0kg" and no "s rest".
3. [ ] (Optional) Add a second day later in the week.
       → Within a week, days are listed Monday to Sunday.

**Coach: assign**
4. [ ] Bottom bar → **Clients** → open the client → Overview → **Assign / Change
       Program** → pick the program → **Assign Program**.
       → The sheet closes with "Program assigned!".
       ↻ Then reopen the client: **Assigned Program** shows the program name
       and "Week 1 of N". Without a relaunch it can still say "No program
       assigned yet". That's the known cache issue, not a failure.

**Client: see it and train it**
5. [ ] ↻ Sign in as the client → open the notifications list.
       → "New Workout Program". This is an in-app entry, not a push notification.
6. [ ] **Home** → the Today card shows:
       - the line **TODAY · ASSIGNED BY YOUR COACH** (the generic "Your Coach";
         the coach's own name is not shown yet);
       - **your workout's title**;
       - badges for its minutes (45 unless you changed it) and "2 exercises";
       - **Begin session**.

       → It must not say "Full Body Strength" or show calories. If it says "No
       session assigned for today" with **Go to your plan**, check that the
       workout is on Week 1, today's weekday, that it was assigned today, and that
       the build includes the dating fix. If all three hold, it's a ❌.
7. [ ] **Workouts** tab → a hero card for today's workout, then **THIS WEEK**,
       which lists every training day in the program with its day chip (today's
       says **Now**). Tap today's row → both exercises are listed.
8. [ ] **Begin session** (from Home or the workout page) → log at least one set →
       finish.
       → The session completes with no error. Close the summary:
       - **Home**: the Today card no longer offers the workout. It says "No
         session assigned for today".
       - **Workouts**: no hero card, and today's row under **THIS WEEK** reads
         **DONE**.

       A training day counts as done once it's finished under this assignment,
       on any day. Re-assigning the program starts every day fresh.
9. [ ] Open **Activity** from Home's **This Week's Progress** section (it has no
       bottom-bar tab). Its "TODAY'S
       WORKOUT" card must match Home. Before step 8 that means the same title,
       the same badges, a **Start** button, no "Full Body Strength" and no
       calories (fixed in PR #18). After step 8, or on a day with nothing
       scheduled, it says "No session assigned for today".

**Coach: see the result**
10. [ ] ↻ Sign in as the coach.
        - **Compliance** (pull down to refresh): the client's **Workouts/wk**
          counts the session. It counts sessions completed since Monday; it does
          not list them.
        - The client's **Progress** tab: **Last Workout** is today's date and
          **Total Logged** went up by one.

        *Known defect: under RECENT SESSIONS the row reads "Workout", not your
        title, with no duration. The screen reads keys the query doesn't
        return. Tracked separately.*

**Re-assign**
11. [ ] Assign a second program to the same client (needs a training day for
        today too).
        → ↻ As the client: Home and Workouts show only the new program; the old
        one is gone. As the coach, after ↻: **Assigned Program** names the new
        one.

## Record the result

For each step, record ✅ / ❌ / ⚠️, the platform (web / iOS / Android) and a
screenshot of any ❌. One ❌ in steps 1-8 or 10 means the beta can't start on
this route. Report it and it becomes the next fix. Items marked *known* above are
⚠️, not ❌.

Signing in has no effect on the live check METRIC-02: sign-ins are not audited
(migration 142's accepted blind spot). The check arranges its own audit row
instead. That fix is merged (PR #15).
