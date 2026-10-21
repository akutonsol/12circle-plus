-- fj17-parq-risk-contract.sql — F-J-17 regression suite.
--
-- WHAT IT PROVES
--   A member can save every required PAR-Q safety declaration, the BEFORE
--   trigger classifies it, and the classification stays server-owned.
--
-- WHY IT EXISTS
--   Migration 115 made risk server-authoritative by computing it inside a
--   BEFORE INSERT OR UPDATE trigger on user_profiles. Its classifier appended
--   three narrative flags as untyped literals to a text[], so PostgreSQL
--   resolved anyarray||anyarray and raised 22P02 malformed array literal. The
--   throw happened in the write path, so the member could not save the
--   declaration at all. Migration 126 casts the three appends to ::text.
--
-- HOW TO READ THE RESULT
--   Every assertion prints one PASS/FAIL line. The suite ends by RAISEing its
--   report, so the whole thing ROLLS BACK: it writes nothing that survives.
--   Run it against an ephemeral local database built from the committed
--   migrations, or against QA under the usual live-evidence gating.
--
--   Against a database at migration 115..125 (pre-126) FJ17-1..FJ17-3 and
--   FJ17-6 FAIL with 22P02 — that is the defect, reproduced.

DO $$
DECLARE
  v_uid  uuid;
  v_res  text := E'\n';
  v_lvl  text;
  v_flg  text;
  v_scr  int;
  v_err  text;
  v_as   text;
BEGIN
  SELECT id INTO v_uid FROM public.user_profiles WHERE role = 'client' ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'FJ17-0 no seeded client profile — the suite cannot run';
  END IF;

  -- Write exactly as the member does: their own JWT, their own row, RLS on.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);
  -- Become the member for the rest of the block where the environment allows
  -- it, so "a member can save this" means the member. A hosted Supabase project
  -- grants `authenticated` table privileges as part of its bootstrap; a bare
  -- local replay of the committed migrations does not, and there the block runs
  -- as the table owner with the member's JWT claims set. Either way the BEFORE
  -- trigger and the classifier -- what F-J-17 is about -- run identically. Table
  -- grants and RLS are the security suite's subject, not this one's.
  IF has_table_privilege('authenticated', 'public.user_profiles', 'UPDATE') THEN
    PERFORM set_config('role', 'authenticated', true);
    v_as := 'authenticated (RLS enforced)';
  ELSE
    v_as := 'table owner + member JWT claims (local replay has no platform grants; RLS not exercised)';
  END IF;

  -- ── FJ17-1 · an active injury declaration ───────────────────────────────
  BEGIN
    UPDATE public.user_profiles
       SET has_injuries = true, injury_locations = 'left knee'
     WHERE id = v_uid;
    SELECT risk_flags INTO v_flg FROM public.user_profiles WHERE id = v_uid;
    v_res := v_res || CASE WHEN v_flg LIKE '%active_injuries%' THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-1  a member can save active_injuries -> flags: ' || coalesce(v_flg,'(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    v_res := v_res || 'FAIL FJ17-1  active_injuries rejected with SQLSTATE ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  -- ── FJ17-2 · a pregnancy declaration ────────────────────────────────────
  BEGIN
    UPDATE public.user_profiles
       SET medical_conditions = 'Pregnancy', has_injuries = false, injury_locations = ''
     WHERE id = v_uid;
    SELECT risk_flags, risk_level INTO v_flg, v_lvl FROM public.user_profiles WHERE id = v_uid;
    v_res := v_res || CASE WHEN v_flg LIKE '%pregnancy%' AND v_lvl = 'moderate' THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-2  a member can save pregnancy -> level ' || coalesce(v_lvl,'(null)')
          || ', flags: ' || coalesce(v_flg,'(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    v_res := v_res || 'FAIL FJ17-2  pregnancy rejected with SQLSTATE ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  -- ── FJ17-3 · a postpartum declaration ───────────────────────────────────
  BEGIN
    UPDATE public.user_profiles SET medical_conditions = 'Postpartum' WHERE id = v_uid;
    SELECT risk_flags INTO v_flg FROM public.user_profiles WHERE id = v_uid;
    v_res := v_res || CASE WHEN v_flg LIKE '%postpartum%' THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-3  a member can save postpartum -> flags: ' || coalesce(v_flg,'(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    v_res := v_res || 'FAIL FJ17-3  postpartum rejected with SQLSTATE ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  -- ── FJ17-4 · a heart-condition declaration, and FJ17-5 its classification ─
  BEGIN
    UPDATE public.user_profiles
       SET parq_answers = '{"1": true}'::jsonb, medical_conditions = ''
     WHERE id = v_uid;
    SELECT risk_level, risk_flags, risk_score INTO v_lvl, v_flg, v_scr
      FROM public.user_profiles WHERE id = v_uid;
    v_res := v_res || CASE WHEN v_lvl IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-4  a member can save heart_condition' || E'\n';
    v_res := v_res || CASE WHEN v_lvl = 'high' AND v_flg LIKE '%heart_condition%' THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-5  heart_condition -> risk_level=' || coalesce(v_lvl,'(null)')
          || ' flags=' || coalesce(v_flg,'(null)') || ' score=' || coalesce(v_scr::text,'(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    v_res := v_res || 'FAIL FJ17-4  heart_condition rejected with SQLSTATE ' || v_err || ': ' || SQLERRM || E'\n';
    v_res := v_res || 'FAIL FJ17-5  classification unreachable' || E'\n';
  END;

  -- ── FJ17-6 · every declaration together, no 22P02 anywhere ──────────────
  BEGIN
    UPDATE public.user_profiles
       SET parq_answers      = '{"1": true, "5": true}'::jsonb,
           medical_conditions = 'Pregnancy,Postpartum',
           has_injuries       = true,
           injury_locations   = 'left knee'
     WHERE id = v_uid;
    SELECT risk_level, risk_flags INTO v_lvl, v_flg FROM public.user_profiles WHERE id = v_uid;
    v_res := v_res || CASE WHEN v_lvl = 'high'
                            AND v_flg LIKE '%heart_condition%'
                            AND v_flg LIKE '%orthopedic_condition%'
                            AND v_flg LIKE '%pregnancy%'
                            AND v_flg LIKE '%postpartum%'
                            AND v_flg LIKE '%active_injuries%'
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-6  all declarations together, no 22P02 -> ' || coalesce(v_flg,'(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    v_res := v_res || 'FAIL FJ17-6  combined declaration rejected with SQLSTATE ' || v_err
          || ': ' || SQLERRM || E'\n';
  END;

  -- ── FJ17-7 · the derived fields are server-owned ────────────────────────
  -- The member supplies a deliberately false, safer-looking classification
  -- alongside a declared heart condition. The trigger must overwrite it.
  BEGIN
    UPDATE public.user_profiles
       SET parq_answers = '{"1": true}'::jsonb,
           medical_conditions = '', has_injuries = false, injury_locations = '',
           risk_level = 'low', risk_flags = '', risk_score = 0
     WHERE id = v_uid;
    SELECT risk_level, risk_flags, risk_score INTO v_lvl, v_flg, v_scr
      FROM public.user_profiles WHERE id = v_uid;
    v_res := v_res || CASE WHEN v_lvl = 'high' AND v_flg LIKE '%heart_condition%' AND v_scr = 1
                       THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-7  a client-supplied classification is discarded -> level='
          || coalesce(v_lvl,'(null)') || ' flags=' || coalesce(v_flg,'(null)')
          || ' score=' || coalesce(v_scr::text,'(null)') || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    v_res := v_res || 'FAIL FJ17-7  rejected with SQLSTATE ' || v_err || ': ' || SQLERRM || E'\n';
  END;

  -- ── FJ17-8 · unrelated profile fields still write ───────────────────────
  BEGIN
    UPDATE public.user_profiles
       SET food_allergies = 'peanuts', sleep_hours = '7-8'
     WHERE id = v_uid;
    SELECT food_allergies INTO v_flg FROM public.user_profiles WHERE id = v_uid;
    v_res := v_res || CASE WHEN v_flg = 'peanuts' THEN 'PASS' ELSE 'FAIL' END
          || ' FJ17-8  unrelated profile fields are unaffected' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = RETURNED_SQLSTATE;
    v_res := v_res || 'FAIL FJ17-8  unrelated field write rejected: ' || v_err || E'\n';
  END;

  -- Everything above is undone by this raise.
  RAISE EXCEPTION E'\n=== F-J-17 PAR-Q RISK CONTRACT ===\nrunning as: %\n%', v_as, v_res;
END;
$$;
