-- fj07-rule-accumulator-contract.sql — F-J-07 (registry SEC-R3) regression suite.
--
-- WHAT IT PROVES
--   Every decision path that accumulates rule labels into a text[] now executes
--   instead of raising 22P02, and each label reaches the caller.
--
-- WHY IT EXISTS
--   `v text[] := '{}'` then `v := v || 'LABEL'` resolves to anyarray||anyarray
--   and fails to read 'LABEL' as an array literal (22P02). Eleven sites across
--   three functions had that shape:
--     build_workout            089:55   RECOVERY_REDUCTION
--     evaluate_week(_engine)   094:52,55,60,65
--     predict_client(_engine)  095:125,127,128,129,130,131
--   Migration 127 casts all eleven to ::text.
--
--   evaluate_week and predict_client were renamed to *_engine by migration 116,
--   which published authorization wrappers under the public names. This suite
--   calls the ENGINES, because they are where the defect lived and where 127
--   fixes it. Authorization is the wrappers' contract and is covered by the
--   security suite -- deliberately not re-tested here.
--
-- HOW TO READ THE RESULT
--   One PASS/FAIL line per assertion. The suite ends by RAISEing its report, so
--   everything it writes ROLLS BACK. Against a database at 000-126 (pre-127),
--   FJ07-1 and FJ07-4..FJ07-9 FAIL with 22P02 -- that is the defect, reproduced.

DO $$
DECLARE
  v_prog   uuid;          -- fixture program for evaluate_week
  v_prog2  uuid;          -- fixture program for predict_client (needs its own history)
  v_subj   uuid;
  v_res    text := E'\n';
  v_j      jsonb;
  v_err    text;
  v_22p02  int := 0;
BEGIN
  SELECT id INTO v_subj FROM public.user_profiles WHERE role = 'client' ORDER BY created_at LIMIT 1;
  IF v_subj IS NULL THEN
    RAISE EXCEPTION 'FJ07-0 no seeded client profile — the suite cannot run';
  END IF;

  INSERT INTO public.workout_programs (name, plan)
       VALUES ('FJ07 fixture — evaluate_week', jsonb_build_object('duration_weeks', 12))
    RETURNING id INTO v_prog;
  INSERT INTO public.workout_programs (name, plan)
       VALUES ('FJ07 fixture — predict_client', jsonb_build_object('duration_weeks', 12))
    RETURNING id INTO v_prog2;

  -- ══ build_workout · the F-J-07 threshold contract, 59 / 60 / 61 ═══════════
  -- The deload branch is the FIRST statement in the function, so it throws
  -- before any candidate is scored. It therefore needs no substrate: this
  -- assertion is independent of F-J-06.
  BEGIN
    v_j := public.build_workout(jsonb_build_object('recovery', 59, 'size', 5));
    v_res := v_res || CASE WHEN (v_j->'rules_triggered') ? 'RECOVERY_REDUCTION'
                            AND (v_j->>'volume_factor')::numeric = 0.8
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-1  recovery 59 → no 22P02, RECOVERY_REDUCTION present, volume_factor '
          || coalesce(v_j->>'volume_factor','(null)') || ', target_size '
          || coalesce(v_j->>'target_size','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-1  recovery 59 raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  BEGIN
    v_j := public.build_workout(jsonb_build_object('recovery', 60, 'size', 5));
    v_res := v_res || CASE WHEN NOT ((v_j->'rules_triggered') ? 'RECOVERY_REDUCTION')
                            AND (v_j->>'volume_factor')::numeric = 1.0
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-2  recovery 60 → threshold not crossed, volume_factor '
          || coalesce(v_j->>'volume_factor','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-2  recovery 60 raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  BEGIN
    v_j := public.build_workout(jsonb_build_object('recovery', 61, 'size', 5));
    v_res := v_res || CASE WHEN NOT ((v_j->'rules_triggered') ? 'RECOVERY_REDUCTION')
                            AND (v_j->>'volume_factor')::numeric = 1.0
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-3  recovery 61 → threshold not crossed, volume_factor '
          || coalesce(v_j->>'volume_factor','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-3  recovery 61 raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  -- ══ evaluate_week_engine · the four branches that threw ═══════════════════
  -- Branch priority (094): injury → fatigue deload → low recovery → adherence
  -- → overload. Each fixture week below selects exactly one branch.
  INSERT INTO public.weekly_feedback (program_id, subject_id, week, completion_pct, recovery, energy, pain, prs)
  VALUES (v_prog, v_subj, 991, 80, 70, 80, '["knee"]'::jsonb, 0),   -- injury
         (v_prog, v_subj, 992, 80, 50, 40, '[]'::jsonb, 0),         -- fatigue deload
         (v_prog, v_subj, 993, 80, 58, 80, '[]'::jsonb, 0),         -- low recovery (already worked)
         (v_prog, v_subj, 994, 50, 70, 80, '[]'::jsonb, 0),         -- adherence
         (v_prog, v_subj, 995, 95, 90, 90, '[]'::jsonb, 0);         -- overload

  BEGIN
    v_j := public.evaluate_week_engine(v_prog, 991);
    v_res := v_res || CASE WHEN v_j->>'action' = 'REPLACE_EXERCISES'
                            AND (v_j->'rules_triggered') ? 'INJURY_ADAPTATION'
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-4  injury branch → action ' || coalesce(v_j->>'action','(null)')
          || ', rules ' || coalesce(v_j->>'rules_triggered','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-4  injury branch raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  BEGIN
    v_j := public.evaluate_week_engine(v_prog, 992);
    v_res := v_res || CASE WHEN v_j->>'action' = 'INSERT_DELOAD'
                            AND (v_j->'rules_triggered') ? 'FATIGUE_DELOAD'
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-5  fatigue-deload branch → action ' || coalesce(v_j->>'action','(null)')
          || ', rules ' || coalesce(v_j->>'rules_triggered','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-5  fatigue-deload branch raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  BEGIN
    v_j := public.evaluate_week_engine(v_prog, 993);
    v_res := v_res || CASE WHEN v_j->>'action' = 'REDUCE_VOLUME'
                            AND (v_j->'rules_triggered') ? 'RECOVERY_PROTECTION'
                            AND (v_j->'rules_triggered') ? 'REPLACE_HIGH_FATIGUE'
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-6  low-recovery branch (array constructor — worked before 127) still intact → '
          || coalesce(v_j->>'rules_triggered','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-6  low-recovery branch raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  BEGIN
    v_j := public.evaluate_week_engine(v_prog, 994);
    v_res := v_res || CASE WHEN v_j->>'action' = 'REDUCE_COMPLEXITY'
                            AND (v_j->'rules_triggered') ? 'ADHERENCE_SUPPORT'
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-7  adherence branch → action ' || coalesce(v_j->>'action','(null)')
          || ', rules ' || coalesce(v_j->>'rules_triggered','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-7  adherence branch raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  BEGIN
    v_j := public.evaluate_week_engine(v_prog, 995);
    v_res := v_res || CASE WHEN v_j->>'action' = 'INCREASE_VOLUME'
                            AND (v_j->'rules_triggered') ? 'PROGRESSIVE_OVERLOAD'
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-8  overload branch → action ' || coalesce(v_j->>'action','(null)')
          || ', rules ' || coalesce(v_j->>'rules_triggered','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-8  overload branch raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  -- ══ predict_client_engine · the deterministic alerts ══════════════════════
  -- Its own program, so the aggregates are the fixture's and nothing else's.
  -- recovery 70 → 60 → 40 gives last < first and avg 56.7 < 65 (recovery_declining);
  -- three weeks, zero PRs and 90% completion gives plateau 'high'
  -- (plateau_approaching). Only these two are asserted: the remaining alerts
  -- depend on the profile's weight/goal columns, which this suite does not set
  -- and must not assume.
  INSERT INTO public.weekly_feedback (program_id, subject_id, week, completion_pct, recovery, energy, pain, prs)
  VALUES (v_prog2, v_subj, 1, 90, 70, 80, '[]'::jsonb, 0),
         (v_prog2, v_subj, 2, 90, 60, 80, '[]'::jsonb, 0),
         (v_prog2, v_subj, 3, 90, 40, 80, '[]'::jsonb, 0);

  BEGIN
    v_j := public.predict_client_engine(v_subj, v_prog2);
    v_res := v_res || CASE WHEN v_j->>'status' = 'ok'
                            AND (v_j->'alerts') ? 'plateau_approaching'
                            AND (v_j->'alerts') ? 'recovery_declining'
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ07-9  deterministic alerts emitted → status '
          || coalesce(v_j->>'status','(null)') || ', alerts '
          || coalesce(v_j->>'alerts','(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    IF v_err = '22P02' THEN v_22p02 := v_22p02 + 1; END IF;
    v_res := v_res || 'FAIL FJ07-9  predict_client_engine raised ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  -- ══ the class-level assertion ═════════════════════════════════════════════
  v_res := v_res || CASE WHEN v_22p02 = 0 THEN 'PASS' ELSE 'FAIL' END
        || ' FJ07-10 no 22P02 malformed-array failure on any decision path: '
        || v_22p02 || ' occurrence(s)' || E'\n';

  -- Teardown is belt and braces; the RAISE below rolls everything back.
  DELETE FROM public.weekly_feedback WHERE program_id IN (v_prog, v_prog2);
  DELETE FROM public.workout_programs WHERE id IN (v_prog, v_prog2);

  RAISE EXCEPTION E'\n=== F-J-07 RULE ACCUMULATOR CONTRACT ===\n%', v_res;
END;
$$;
