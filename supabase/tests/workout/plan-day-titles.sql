-- Regression: generated program days have distinguishable titles.
--
-- Pins migration 052's rule, which migration 077 silently reverted by rebuilding
-- generate_client_plan() from migration 048. Every assertion below FAILED
-- against the database before migration 121.
--
-- Titles are a LABEL, not an identity. Nothing here asserts that anything is
-- keyed by title — sessions are keyed by workout id (migration 103,
-- `sessionStatusFor`). What is asserted is that a client can tell Monday's
-- session from Thursday's.
--
-- Runs inside one DO block that ends by raising, so it ALWAYS ROLLS BACK.
--
--   supabase db query --linked --file supabase/tests/workout/plan-day-titles.sql
--
-- QA only. A run containing `FAIL` anywhere is a failing suite.

do $$
declare
  v_res text := '';
  v_got text[];
  v_n int;
begin
  -- ── The rule itself, over every split the generator can produce ───────────

  -- 3-day: one focus, three times. 052's motivating case.
  v_got := public.plan_day_titles(array['full_body','full_body','full_body']);
  v_res := v_res || case
      when v_got = array['Full Body A','Full Body B','Full Body C']
      then 'PASS' else 'FAIL' end
    || ' TITLE-1  3-day full body → ' || array_to_string(v_got, ' | ') || E'\n';

  -- 4-day upper/lower: two focuses, twice each.
  v_got := public.plan_day_titles(array['upper','lower','upper','lower']);
  v_res := v_res || case
      when v_got = array['Upper Body A','Lower Body A','Upper Body B','Lower Body B']
      then 'PASS' else 'FAIL' end
    || ' TITLE-2  4-day upper/lower → ' || array_to_string(v_got, ' | ') || E'\n';

  -- 5-day: every focus appears once, so NOTHING is suffixed. A blanket suffix
  -- would be just as wrong as none.
  v_got := public.plan_day_titles(array['push','pull','legs','upper','lower']);
  v_res := v_res || case
      when v_got = array['Push Day','Pull Day','Leg Day','Upper Body','Lower Body']
      then 'PASS' else 'FAIL' end
    || ' TITLE-3  5-day all-distinct → ' || array_to_string(v_got, ' | ') || E'\n';

  -- 6-day push/pull/legs twice.
  v_got := public.plan_day_titles(array['push','pull','legs','push','pull','legs']);
  v_res := v_res || case
      when v_got = array['Push Day A','Pull Day A','Leg Day A',
                         'Push Day B','Pull Day B','Leg Day B']
      then 'PASS' else 'FAIL' end
    || ' TITLE-4  6-day PPL×2 → ' || array_to_string(v_got, ' | ') || E'\n';

  -- The case 052 never saw: migration 077's focus bias rewrites the LAST day,
  -- so an upper/lower/upper/lower week biased toward "upper" becomes
  -- upper/lower/upper/upper — three Upper Body days. The rule must cover the
  -- split as finally set, not as originally chosen.
  v_got := public.plan_day_titles(array['upper','lower','upper','upper']);
  v_res := v_res || case
      when v_got = array['Upper Body A','Lower Body','Upper Body B','Upper Body C']
      then 'PASS' else 'FAIL' end
    || ' TITLE-5  bias-induced duplicate → ' || array_to_string(v_got, ' | ') || E'\n';

  -- Degenerate inputs must not throw.
  v_got := public.plan_day_titles(array[]::text[]);
  v_res := v_res || case when coalesce(array_length(v_got,1),0) = 0
      then 'PASS' else 'FAIL' end || ' TITLE-6  empty split handled' || E'\n';

  v_got := public.plan_day_titles(array['full_body']);
  v_res := v_res || case when v_got = array['Full Body'] then 'PASS' else 'FAIL' end
    || ' TITLE-7  single day is not suffixed → ' || array_to_string(v_got, ' | ') || E'\n';

  -- ── The generator is wired to the rule ────────────────────────────────────
  select count(*) into v_n from pg_proc
   where proname = 'generate_client_plan'
     and prosrc like '%plan_day_titles%';
  v_res := v_res || case when v_n = 1 then 'PASS' else 'FAIL' end
    || ' TITLE-8  generate_client_plan() uses plan_day_titles()' || E'\n';

  -- …and applies it AFTER the focus bias, not before.
  select count(*) into v_n from pg_proc
   where proname = 'generate_client_plan'
     and position('v_split[v_days] := v_focus_day' in prosrc)
         < position('plan_day_titles(v_split)' in prosrc);
  v_res := v_res || case when v_n = 1 then 'PASS' else 'FAIL' end
    || ' TITLE-9  titles computed after the focus bias is applied' || E'\n';

  -- ── Stored data ──────────────────────────────────────────────────────────
  select count(*) into v_n from (
    select pw.program_id
      from program_workouts pw join workout_programs p on p.id = pw.program_id
     where p.coach_id is null
     group by pw.program_id, pw.title having count(*) > 1) d;
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' TITLE-10 self-generated programs with duplicate day titles: ' || v_n || E'\n';

  -- Coach-authored titles are the coach's own and are never rewritten.
  select count(*) into v_n from program_workouts pw
    join workout_programs p on p.id = pw.program_id
   where p.coach_id is not null and pw.title ~ ' [A-Z]$';
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' TITLE-11 coach-authored titles left untouched: ' || v_n || ' suffixed' || E'\n';

  -- Titles are still not an identity: workout ids remain the key, and they are
  -- unique per program regardless of what the labels say.
  select count(*) into v_n from (
    select program_id, id from program_workouts group by program_id, id having count(*) > 1) d;
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' TITLE-12 workout identity is the id, and it is unique' || E'\n';

  -- ── End to end: run the real generator and read back what it wrote ───────
  --
  -- Everything above pins the rule and the stored data. This runs
  -- generate_client_plan() itself, as the QA test client, and inspects the
  -- program it produces. It is the only assertion that proves the wiring rather
  -- than the parts. All of its writes are undone by the raise below.
  perform set_config('request.jwt.claims',
    '{"sub":"5470a95f-bcae-4e01-b2be-7c16964fa432","role":"authenticated"}', true);
  perform public.generate_client_plan();

  select array_agg(pw.title order by pw.sort_order) into v_got
    from program_workouts pw
   where pw.program_id = (
     select a.program_id from workout_program_assignments a
      where a.client_id = '5470a95f-bcae-4e01-b2be-7c16964fa432'
        and a.coach_id is null and a.status = 'active'
      order by a.assigned_at desc limit 1);

  v_res := v_res || case
      when coalesce(array_length(v_got, 1), 0) > 0 then 'PASS' else 'FAIL' end
    || ' TITLE-13 generator produced a program → '
    || coalesce(array_to_string(v_got, ' | '), '(none)') || E'\n';

  select count(*) into v_n from (select unnest(v_got) t group by t having count(*) > 1) d;
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' TITLE-14 a freshly generated program has no duplicate day titles: '
    || v_n || ' duplicated' || E'\n';

  -- The titles are 052's vocabulary, suffixed only where a focus repeats — not
  -- some new scheme, and not blanket-numbered.
  select count(*) into v_n from unnest(v_got) t
   where t !~ '^(Full Body|Upper Body|Lower Body|Push Day|Pull Day|Leg Day|Workout)( [A-Z])?$';
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' TITLE-15 titles use 052''s vocabulary and suffix form: '
    || v_n || ' off-contract' || E'\n';

  perform set_config('request.jwt.claims', '', true);

  raise exception E'\n=== PLAN DAY TITLES ===\n%', v_res;
end;
$$;
