-- Phase 2 — live workout-domain contract regression, run against QA.
--
-- Every assertion here failed against the pre-Phase-2 database; each one names
-- the defect it pins. The whole script runs inside one DO block that ends by
-- RAISEing its report, so it ALWAYS ROLLS BACK: no fixture it creates survives,
-- and it is safe to run repeatedly against a populated environment.
--
-- SAFETY: QA only. This asserts on real rows and creates probe rows; it must
-- never be pointed at production.
--
--   supabase db query --linked --file supabase/tests/workout/phase2-contract.sql
--
-- A run that ends with `FAIL` anywhere in the report is a failing suite.

do $$
declare
  -- SEC-11 / FG-2a. This was hardcoded to a single real QA account:
  --
  --     v_client uuid := '5470a95f-bcae-4e01-b2be-7c16964fa432';
  --
  -- The suite then inserts an `in_progress` session for it (below), and
  -- `workout_sessions_one_active_per_user` permits exactly one active session
  -- per user. So the moment that shared account had a live session -- ordinary
  -- QA usage is enough, and it is not a defect -- the fixture insert was
  -- refused with 23505 and the suite died before emitting its report banner.
  -- Observed in CI runs 36596636664 and 36603451032.
  --
  -- This was NOT a leaked fixture: the DO block ends by RAISEing its report, so
  -- everything here rolls back and the suite cannot leave a session behind. The
  -- defect was an unsound PRECONDITION -- the suite asserted on state it did
  -- not own.
  --
  -- The client is now chosen deterministically from the demo fixture population
  -- and must already satisfy the precondition. Shared QA state is never
  -- deleted or mutated to make room: a user with a live session is simply not
  -- selected. `order by id` keeps the choice stable across runs.
  v_client uuid;
  v_prog uuid; v_sess uuid; v_done uuid; v_res text := ''; v_n int; v_txt text;

  procedure_note text;
begin
  select p.id into v_client
    from public.user_profiles p
   where p.is_demo is true
     and not exists (
       select 1 from public.workout_sessions s
        where s.user_id = p.id and s.status = 'in_progress')
   order by p.id
   limit 1;

  if v_client is null then
    -- Fail loudly and specifically. A suite that silently skips its own setup
    -- is worse than one that fails, and "no eligible fixture" is a different
    -- diagnosis from "an assertion broke".
    raise exception
      'PHASE 2 SETUP: no demo user_profiles row without an active workout_sessions '
      'row. Seed one (setup-identities.mjs flags its identities is_demo) or clear a '
      'stale in_progress session for a DEMO account -- never for a real one.';
  end if;
  -- ── AFTER-7 · every stored row is canonical ───────────────────────────────
  select count(*) into v_n from program_workouts
   where not public.is_canonical_exercise_prescription(exercises);
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
        || ' AFTER-7a  non-canonical program_workouts rows: ' || v_n || E'\n';

  select count(*) into v_n from program_workouts where day_of_week ~ '^[1-7]$';
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
        || ' AFTER-7b  numeric day_of_week rows: ' || v_n || E'\n';

  -- Load survives under the canonical key rather than being read as 0.
  select count(*) into v_n
    from program_workouts pw, jsonb_array_elements(pw.exercises) e
   where (e.value->>'name') = 'Bench Press'
     and (e.value->>'weight_kg')::numeric = 60;
  v_res := v_res || case when v_n > 0 then 'PASS' else 'FAIL' end
        || ' AFTER-7c  seeded 60kg bench press readable as weight_kg: ' || v_n || E'\n';

  -- Every element carries an identity.
  select count(*) into v_n
    from program_workouts pw, jsonb_array_elements(pw.exercises) e
   where coalesce(btrim(e.value->>'exercise_instance_id'), '') = '';
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
        || ' AFTER-7d  exercise elements with no instance id: ' || v_n || E'\n';

  -- ── AFTER-8 · the Phase 1 boundary is untouched ───────────────────────────
  select count(*) into v_n from pg_proc where proname = 'can_read_program';
  v_res := v_res || case when v_n = 1 then 'PASS' else 'FAIL' end
        || ' AFTER-8a  can_read_program() still present' || E'\n';

  select count(*) into v_n from pg_policies
   where tablename = 'program_workouts' and cmd = 'SELECT'
     and qual like '%can_read_program%';
  v_res := v_res || case when v_n = 1 then 'PASS' else 'FAIL' end
        || ' AFTER-8b  program_workouts SELECT still gated by can_read_program' || E'\n';

  select count(*) into v_n from information_schema.role_table_grants
   where table_name = 'program_workouts' and grantee = 'anon';
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
        || ' AFTER-8c  anon grants on program_workouts: ' || v_n || E'\n';

  -- ── Contract enforcement ──────────────────────────────────────────────────
  insert into workout_programs(coach_id, name, description, goal, difficulty, duration_weeks, is_template)
  values (null, 'P2-PROBE', 'phase 2 contract probe', 'general', 'intermediate', 1, false)
  returning id into v_prog;

  -- AFTER-1a: a legacy dialect is canonicalised on write, not rejected.
  insert into program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
  values (v_prog, 1, '3', 'P2-PROBE legacy',
    '[{"name":"Bench Press","sets":3,"reps":"10","rest":60}]'::jsonb, 0);
  select (exercises->0)::text, day_of_week into v_txt, procedure_note
    from program_workouts where program_id = v_prog;
  v_res := v_res || case
      when v_txt like '%"reps": 10%' and v_txt like '%"rest_seconds": 60%'
       and v_txt like '%"weight_kg": null%' and v_txt like '%exercise_instance_id%'
       and procedure_note = 'Wednesday'
      then 'PASS' else 'FAIL' end
    || ' AFTER-1a  legacy row canonicalised: ' || v_txt
    || ' day=' || procedure_note || E'\n';

  -- AFTER-1b: genuinely ambiguous data is refused, not guessed at.
  begin
    insert into program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
    values (v_prog, 1, 'Monday', 'P2-PROBE range',
      '[{"name":"Bench Press","sets":3,"reps":"8-12"}]'::jsonb, 1);
    v_res := v_res || 'FAIL AFTER-1b  a rep RANGE was accepted' || E'\n';
  exception when check_violation then
    v_res := v_res || 'PASS AFTER-1b  rep range refused by the CHECK' || E'\n';
  end;

  -- AFTER-1c: an unnamed exercise is refused.
  begin
    insert into program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
    values (v_prog, 1, 'Monday', 'P2-PROBE unnamed',
      '[{"sets":3,"reps":10}]'::jsonb, 2);
    v_res := v_res || 'FAIL AFTER-1c  an unnamed exercise was accepted' || E'\n';
  exception when check_violation then
    v_res := v_res || 'PASS AFTER-1c  unnamed exercise refused' || E'\n';
  end;

  -- ── Set identity ──────────────────────────────────────────────────────────
  insert into workout_sessions(user_id, workout_title, status, workout_id)
  values (v_client, 'P2-PROBE session', 'in_progress', 'p2-probe')
  returning id into v_sess;

  insert into workout_set_logs(session_id, user_id, exercise_name,
    exercise_instance_id, set_number, reps, weight_kg, set_id, completed)
  values (v_sess, v_client, 'Bench Press', 'inst-a', 1, 8, 60, 'inst-a:s1', true);

  -- AFTER-2: the SAME exercise name, a second instance, its own set 1.
  begin
    insert into workout_set_logs(session_id, user_id, exercise_name,
      exercise_instance_id, set_number, reps, weight_kg, set_id, completed)
    values (v_sess, v_client, 'Bench Press', 'inst-b', 1, 10, 50, 'inst-b:s1', true);
    v_res := v_res || 'PASS AFTER-2   duplicate exercise names no longer collide' || E'\n';
  exception when unique_violation then
    v_res := v_res || 'FAIL AFTER-2   still 23505: ' || SQLERRM || E'\n';
  end;

  -- AFTER-3: after a swap the new instance carries new set identities.
  begin
    insert into workout_set_logs(session_id, user_id, exercise_name,
      exercise_instance_id, set_number, reps, weight_kg, set_id, completed)
    values (v_sess, v_client, 'Dumbbell Press', 'swap-1', 1, 10, 30, 'swap-1:s1', true);
    v_res := v_res || 'PASS AFTER-3   post-swap set log inserts cleanly' || E'\n';
  exception when unique_violation then
    v_res := v_res || 'FAIL AFTER-3   still 23505: ' || SQLERRM || E'\n';
  end;

  -- …and the replaced exercise's own log is untouched.
  select count(*) into v_n from workout_set_logs
   where session_id = v_sess and set_id = 'inst-a:s1'
     and exercise_name = 'Bench Press' and completed;
  v_res := v_res || case when v_n = 1 then 'PASS' else 'FAIL' end
        || ' AFTER-3b  the replaced exercise keeps its own completed log' || E'\n';

  -- AFTER-5: a row with no identity is refused.
  begin
    insert into workout_set_logs(session_id, user_id, exercise_name,
      set_number, reps, weight_kg, completed)
    values (v_sess, v_client, 'Nameless', 1, 8, 20, true);
    v_res := v_res || 'FAIL AFTER-5   a set log with no set_id was accepted' || E'\n';
  exception when others then
    v_res := v_res || 'PASS AFTER-5   set log without an identity refused' || E'\n';
  end;

  -- ── AFTER-4 · completed history is immutable ──────────────────────────────
  begin
    update workout_set_logs set completed = false
     where session_id = v_sess and set_id = 'inst-a:s1';
    v_res := v_res || 'FAIL AFTER-4a  a completed set was un-completed' || E'\n';
  exception when others then
    v_res := v_res || 'PASS AFTER-4a  un-completing a confirmed set refused' || E'\n';
  end;

  begin
    update workout_set_logs set exercise_instance_id = 'swap-1'
     where session_id = v_sess and set_id = 'inst-a:s1';
    v_res := v_res || 'FAIL AFTER-4b  a set log was re-attributed to another instance' || E'\n';
  exception when others then
    v_res := v_res || 'PASS AFTER-4b  re-attribution to another instance refused' || E'\n';
  end;

  -- A deliberate correction of a recorded result is still allowed: the product
  -- has an explicit correction flow, and that is a different thing from a set
  -- silently changing underneath the client.
  begin
    update workout_set_logs set weight_kg = 62.5
     where session_id = v_sess and set_id = 'inst-a:s1';
    v_res := v_res || 'PASS AFTER-4c  an explicit correction is still permitted' || E'\n';
  exception when others then
    v_res := v_res || 'FAIL AFTER-4c  correction blocked: ' || SQLERRM || E'\n';
  end;

  -- ── AFTER-6 · terminal session states ─────────────────────────────────────
  insert into workout_sessions(user_id, workout_title, status, workout_id, workout_snapshot)
  values (v_client, 'P2-PROBE done', 'completed', 'p2-probe-done', '{"id":"x"}'::jsonb)
  returning id into v_done;

  begin
    update workout_sessions set status = 'in_progress' where id = v_done;
    v_res := v_res || 'FAIL AFTER-6a  a completed session was re-opened' || E'\n';
  exception when others then
    v_res := v_res || 'PASS AFTER-6a  re-opening a completed session refused' || E'\n';
  end;

  begin
    update workout_sessions set workout_snapshot = '{"id":"tampered"}'::jsonb
     where id = v_done;
    v_res := v_res || 'FAIL AFTER-6b  a finished session''s snapshot was rewritten' || E'\n';
  exception when others then
    v_res := v_res || 'PASS AFTER-6b  finished session snapshot is immutable' || E'\n';
  end;

  -- Abandoning is a legitimate transition out of in_progress, and it must not
  -- take the set logs with it.
  update workout_sessions set status = 'abandoned' where id = v_sess;
  select count(*) into v_n from workout_set_logs where session_id = v_sess;
  v_res := v_res || case when v_n >= 3 then 'PASS' else 'FAIL' end
        || ' AFTER-6c  abandoning preserves set logs: ' || v_n || ' rows' || E'\n';

  -- ── Teardown (belt and braces; the RAISE below rolls everything back) ─────
  delete from workout_set_logs where session_id = v_sess;
  delete from workout_sessions where id in (v_sess, v_done);
  delete from program_workouts where program_id = v_prog;
  delete from workout_programs where id = v_prog;

  raise exception E'\n=== PHASE 2 WORKOUT CONTRACT ===\n%', v_res;
end;
$$;
