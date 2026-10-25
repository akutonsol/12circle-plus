-- Migration 186. The coach programme engine produces complete, canonical training
-- days again — or fails explicitly, changing nothing.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["186"] (owner approval of "route A", 2026-10-25): it ships
-- in one push AFTER 182, 183, 184 and 185, in that order, never alone and never
-- out of order. Verified only on a local replay; not on QA, not in production.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE REGRESSION, VERIFIED AGAINST SOURCE AND THE REPLAYED CATALOG
-- ═══════════════════════════════════════════════════════════════════════════
--   093  materialize_program_week: writes coalesce(selected,'[]') straight into
--        program_workouts.exercises — no sets/reps, a padded lower-case weekday
--        (`to_char(now(),'day')`), and an empty selection saved as an empty day.
--   116  renames that function to materialize_program_week_engine and puts an
--        authorization wrapper (can_act_on_program) in front of it.
--   119  replaces the PUBLIC function with a corrected body: raises on an empty
--        selection, maps the selection into the canonical prescription
--        (sets/reps/rest from the caller's context, weight_kg null), and writes
--        real day names. It did not touch the _engine.
--   124  restores 116's wrapper over the PUBLIC name — which delegates to the
--        _engine, i.e. 093's body. Both of 119's corrections stopped running.
--   Catalog of a 000-181 replay: the engine body contains `to_char(now(),'day')`
--   and no guard; the wrapper carries the authorization; authenticated cannot
--   execute the engine directly.
--
-- Observed on that replay, before this migration:
--   * intelligence substrate EMPTY  -> 3 days written with 0 exercises,
--     `sessions_created: 3` returned as success;
--   * substrate POPULATED           -> 23514: the canonical-prescription CHECK on
--     program_workouts rejects the engine's {id,name,pattern,score} objects.
-- Populating the substrate alone therefore does not make the engine work.
--
-- Migration 183 (pending) restores only the empty-selection guard. This migration
-- supersedes it: applied after 183 it replaces 183's body, applied without it it
-- is complete on its own.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT THIS RESTORES, AND THE THREE THINGS IT ADDS
-- ═══════════════════════════════════════════════════════════════════════════
-- Restores 119's behaviour inside the ENGINE, which is where the 124 wrapper sends
-- every call:
--   * each selected exercise becomes a canonical prescription: a fresh
--     exercise_instance_id, name, position, sets, reps, weight_kg NULL (the engine
--     does not prescribe load — PD-A01's interim contract), rest_seconds from the
--     context, and exercise_id / movement_pattern kept for traceability;
--   * sets and reps come from the caller's context (`sets`, `reps`,
--     `rest_seconds`), defaulting to 119's 3 x 10 when absent;
--   * day_of_week is a full English day name (WORKOUT_DOMAIN_CONTRACT §3.4).
-- Adds, because the prompt that authorized this draft requires it:
--   1. ALL-OR-NOTHING. Every session is selected and validated BEFORE anything is
--      deleted or written. Any empty selection raises ENGINE_NO_SELECTION and the
--      week is left exactly as it was (and the function's transaction is rolled
--      back, decision traces included).
--   2. NO SILENT OVERWRITE. 093/119 deleted the week's existing days on every call,
--      which destroys a coach's edits. A week that already has days is replaced
--      only when the caller passes `"replace_existing": true`; otherwise
--      ENGINE_WEEK_EXISTS is raised and nothing changes.
--   3. NO DUPLICATE WEEKS. program_workouts has no unique key on
--      (program_id, week_number), so two concurrent calls could each delete-then-
--      insert. The programme row is locked FOR UPDATE first, serializing them.
--
-- Errors carry a stable prefix (ENGINE_NO_SELECTION / ENGINE_WEEK_EXISTS /
-- ENGINE_BAD_PRESCRIPTION / ENGINE_NO_PLAN / ENGINE_NO_WEEK) so the app can map them to coach-facing copy
-- without parsing prose. SQLSTATE stays P0001 (plain RAISE), as before.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- AUTHORIZATION, POSTURE, COMPATIBILITY
-- ═══════════════════════════════════════════════════════════════════════════
--   * Unchanged: callers reach the engine only through the public wrapper, which
--     checks can_act_on_program (124). The engine stays revoked from PUBLIC, anon
--     and authenticated — restated below because CREATE OR REPLACE keeps the ACL
--     but a reader should not have to know that.
--   * SECURITY DEFINER with search_path pinned (Gate 0.14 / migration 122).
--   * Signature and RETURNS unchanged, so the wrapper needs no change.
--   * Existing data: no row is read or rewritten except the target week of the
--     target programme, and only on success. The NOT VALID check on
--     program_workouts is untouched.
--   * Callers: ONE, and it is OFF. Program Builder's "Generate week 1"
--     (dynamic_program_builder_screen.dart via CoachProgramService.materializeWeek)
--     is compiled in behind ENGINE_WEEK_GENERATION, which defaults to false and is
--     set by no build config. No edge function, live suite or CI step calls it.
--     The flag must stay off for any build whose database lacks this migration.
--
-- KNOWN LIMITATION — replacement cannot tell engine days from coach edits.
-- program_workouts has no provenance column and no timestamps, so when a caller
-- passes "replace_existing": true the whole week is replaced, coach edits
-- included. The database makes that an EXPLICIT act (only a JSON true, never a
-- default); the coach-facing UI must confirm it in words before sending it.
-- If a client has already logged a session against one of those days and
-- workout_sessions.program_workout_id is populated (I-WRK-03, gated on PD-B21),
-- the DELETE fails on the foreign key and the whole call is rolled back — a safe
-- failure, but not a friendly one.
--
-- ROLLBACK LIMITATION: the previous engine body is 093's. Rolling back means
-- re-creating that body, which reinstates the defect. Capture
-- pg_get_functiondef('public.materialize_program_week_engine(uuid,integer,jsonb)')
-- before applying.

BEGIN;

CREATE OR REPLACE FUNCTION public.materialize_program_week_engine(
  p_program_id uuid, p_week integer, p_context jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_plan     jsonb;
  v_week     jsonb;
  v_split    jsonb;
  v_vol      numeric;
  v_base     int;
  v_sets     int;
  v_reps     int;
  v_rest     int;
  v_replace  boolean;
  v_existing int;
  v_ctx      jsonb;
  v_result   jsonb;
  v_selected jsonb;
  v_built    jsonb := '[]'::jsonb;   -- [{label, trace_id, exercises}]
  v_sessions jsonb := '[]'::jsonb;
  v_s        jsonb;
  i          int;
BEGIN
  -- 3. Serialize concurrent materializations of the same programme.
  SELECT plan INTO v_plan FROM workout_programs WHERE id = p_program_id FOR UPDATE;
  IF v_plan IS NULL THEN
    RAISE EXCEPTION 'ENGINE_NO_PLAN: programme % has no plan to materialize', p_program_id;
  END IF;

  SELECT w INTO v_week FROM jsonb_array_elements(v_plan->'weeks') w
   WHERE (w->>'week')::int = p_week;
  IF v_week IS NULL THEN
    RAISE EXCEPTION 'ENGINE_NO_WEEK: week % is not in the plan of programme %', p_week, p_program_id;
  END IF;

  v_split   := coalesce(v_week->'split', '[]'::jsonb);
  v_vol     := coalesce((v_week->>'volume_multiplier')::numeric, 1.0);
  v_base    := coalesce((p_context->>'size')::int, 5);
  v_sets    := coalesce(public._wk_int(p_context->'sets'), 3);
  v_reps    := coalesce(public._wk_int(p_context->'reps'), 10);
  v_rest    := public._wk_int(p_context->'rest_seconds');
  -- Only a JSON `true` replaces anything. A string ("true", "yes") or a missing
  -- key is NOT consent to delete a week's days.
  v_replace := coalesce(p_context->'replace_existing' = 'true'::jsonb, false);

  -- A prescription value that is PRESENT but not a whole number ("8-12", "ten",
  -- 7.5) is refused, not replaced by the 3 x 10 default: silently substituting a
  -- number the caller did not give is inventing a prescription. Absent or null
  -- still means "use the default". Bounds mirror the canonical CHECK.
  IF (p_context ? 'sets' AND jsonb_typeof(p_context->'sets') <> 'null'
        AND (public._wk_int(p_context->'sets') IS NULL OR v_sets < 1))
  OR (p_context ? 'reps' AND jsonb_typeof(p_context->'reps') <> 'null'
        AND (public._wk_int(p_context->'reps') IS NULL OR v_reps < 0))
  OR (p_context ? 'rest_seconds' AND jsonb_typeof(p_context->'rest_seconds') <> 'null'
        AND (v_rest IS NULL OR v_rest < 0)) THEN
    RAISE EXCEPTION 'ENGINE_BAD_PRESCRIPTION: sets, reps and rest_seconds must be whole '
      'numbers (sets >= 1, reps >= 0, rest_seconds >= 0); got sets=%, reps=%, rest_seconds=%. '
      'Nothing was changed.',
      p_context->'sets', p_context->'reps', p_context->'rest_seconds';
  END IF;

  IF jsonb_array_length(v_split) = 0 THEN
    RAISE EXCEPTION 'ENGINE_NO_WEEK: week % of programme % has no sessions in its split', p_week, p_program_id;
  END IF;

  -- 2. Never overwrite a week silently.
  SELECT count(*) INTO v_existing FROM program_workouts
   WHERE program_id = p_program_id AND week_number = p_week;
  IF v_existing > 0 AND NOT v_replace THEN
    RAISE EXCEPTION 'ENGINE_WEEK_EXISTS: week % of programme % already has % training day(s). '
      'Nothing was changed. Pass "replace_existing": true to regenerate it.',
      p_week, p_program_id, v_existing;
  END IF;

  -- 1. Build and validate EVERY session before writing anything.
  FOR i IN 0 .. jsonb_array_length(v_split) - 1 LOOP
    v_ctx := p_context || jsonb_build_object(
      'size', greatest(2, round(v_base * v_vol)),
      'recovery', coalesce((p_context->>'recovery')::int, 75));
    v_result   := public.generate_workout(v_ctx, (p_context->>'subject')::uuid);
    v_selected := coalesce(v_result->'selected', '[]'::jsonb);

    IF jsonb_typeof(v_selected) <> 'array' OR jsonb_array_length(v_selected) = 0 THEN
      RAISE EXCEPTION 'ENGINE_NO_SELECTION: the coaching engine selected no exercises for '
        'week %, session "%" of programme %. Nothing was saved. The exercise intelligence '
        'library is not populated yet, or this client''s equipment and injury filters '
        'exclude every exercise.',
        p_week, coalesce(v_split->>i, (i + 1)::text), p_program_id;
    END IF;

    v_built := v_built || jsonb_build_object(
      'label', v_split->>i,
      'trace_id', v_result->'trace_id',
      'exercises', (
        SELECT jsonb_agg(jsonb_build_object(
                 'exercise_instance_id', gen_random_uuid()::text,
                 'exercise_id',          s.value->>'id',
                 'name',                 s.value->>'name',
                 'position',             (s.ordinality - 1)::int,
                 'sets',                 v_sets,
                 'reps',                 v_reps,
                 'weight_kg',            null,
                 'rest_seconds',         public._wk_jint(v_rest),
                 'rpe',                  null,
                 'tempo',                null,
                 'duration_seconds',     null,
                 'notes',                null,
                 'movement_pattern',     s.value->>'pattern')
               ORDER BY s.ordinality)
          FROM jsonb_array_elements(v_selected) WITH ORDINALITY s(value, ordinality)));
  END LOOP;

  -- Only now is anything changed.
  IF v_existing > 0 THEN
    DELETE FROM program_workouts WHERE program_id = p_program_id AND week_number = p_week;
  END IF;

  i := 0;
  FOR v_s IN SELECT value FROM jsonb_array_elements(v_built) LOOP
    INSERT INTO program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
    VALUES (p_program_id, p_week,
      (ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])[least(i + 1, 7)],
      format('Week %s · %s', p_week, v_s->>'label'),
      v_s->'exercises', i);
    v_sessions := v_sessions || jsonb_build_object(
      'session',   v_s->>'label',
      'trace_id',  v_s->'trace_id',
      'exercises', jsonb_array_length(v_s->'exercises'));
    i := i + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'week', p_week,
    'sessions_created', i,
    'replaced_existing', v_existing > 0,
    'sessions', v_sessions);
END;
$$;

REVOKE ALL ON FUNCTION public.materialize_program_week_engine(uuid, integer, jsonb)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.materialize_program_week_engine(uuid, integer, jsonb) IS
  'Coach programme engine (186): materializes one plan week into canonical training '
  'days — sets/reps from context (default 3x10), weight_kg null, real day names — or '
  'raises ENGINE_NO_SELECTION / ENGINE_WEEK_EXISTS / ENGINE_BAD_PRESCRIPTION / ENGINE_NO_PLAN / ENGINE_NO_WEEK '
  'and changes nothing. Existing days are replaced only with "replace_existing": true. '
  'Reached only through materialize_program_week (authorization wrapper, 124).';

COMMIT;
