-- Migration 119: one canonical prescription contract for program_workouts.
--
-- `program_workouts.exercises` was `jsonb DEFAULT '[]'` with no schema, no
-- CHECK and no validation. Six writers emitted six different shapes and one
-- reader had to guess:
--
--   _plan_day_exercises() (047/077)  {name, sets:int, reps:int, rest_seconds}
--   program_builder_screen           {name, sets:int, reps:TEXT, rest:int}
--   materialize_program_week() (093) {id, name, pattern, score}  -- no prescription
--   seeds/test_accounts.sql          {name, sets, reps, weight_kg, rest_seconds}
--   tool/live_integration_test.dart  {name, sets, reps:TEXT, rest:int}
--   ai-generate-workout              {name, sets, reps, rest_seconds, tempo, ...}
--
--   programWorkoutToWorkout()        {exercise_id|id, name, sets:int, reps:int,
--                                     weight:num, rest_seconds:int, set_details[]}
--
-- The consequences were not cosmetic:
--
--   * NO writer emitted `weight`, so the codec's `(e['weight'] ?? 0)` produced
--     0 kg for every exercise of every program, from every source — including
--     rows that carried a real prescribed load under `weight_kg`. Verified live
--     against QA: a 60 kg bench press reached the client as 0 kg.
--   * The coach UI wrote `rest`; the reader read `rest_seconds`. A coach's
--     60 s rest was discarded and replaced with the codec's 90 s default.
--   * The coach UI wrote `reps` as text. Dart's `as int?` THROWS on a String,
--     and the provider's `catch (_) { return []; }` turned that throw into "you
--     have no program". Authoring one exercise erased the client's program.
--
-- Repairing those individually would leave the contract undefined and the next
-- writer would break it again. This migration makes the shape a property of the
-- database instead:
--
--   1. a canonicalizing trigger — every write is normalised at the boundary, so
--      a writer that still speaks a legacy dialect produces canonical rows;
--   2. a validation function + CHECK — anything that cannot be canonicalised is
--      REJECTED at write time rather than mis-read at read time;
--   3. existing rows are migrated in place;
--   4. the generators are rewritten to emit the contract directly.
--
-- Canonical shape (docs/WORKOUT_DOMAIN_CONTRACT.md §3):
--
--   { "exercise_instance_id": text,      -- required, identity
--     "name": text,                      -- required
--     "position": int,                   -- derived from array order
--     "sets": int >= 1,                  -- required
--     "reps": int >= 0,                  -- required
--     "weight_kg": number|null,          -- REQUIRED KEY, nullable value
--     "rest_seconds": int|null, "rpe": number|null, "tempo": text|null,
--     "duration_seconds": int|null, "notes": text|null,
--     "exercise_id": text|null, "set_details": array|absent, ... }
--
-- `weight_kg: null` means NO PRESCRIBED LOAD and the client renders an absence.
-- It is never 0. `0` is a prescribed zero. Conflating them is what made every
-- program read as an instruction to lift nothing.

-- ── 1. Type helpers ─────────────────────────────────────────────────────────

-- A jsonb value as an integer, or NULL when it is not unambiguously one.
-- Accepts a JSON number that is whole, and a string of digits — "10" is
-- unambiguously ten. It does NOT accept "8-12": a rep range is not a
-- prescription this product supports, and picking one end of it would be
-- inventing a prescription no coach wrote.
CREATE OR REPLACE FUNCTION public._wk_int(v jsonb)
RETURNS int LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF v IS NULL OR jsonb_typeof(v) = 'null' THEN RETURN NULL; END IF;
  IF jsonb_typeof(v) = 'number' THEN
    IF (v::numeric) <> trunc(v::numeric) THEN RETURN NULL; END IF;
    RETURN (v::numeric)::int;
  END IF;
  IF jsonb_typeof(v) = 'string' AND btrim(v #>> '{}') ~ '^-?[0-9]+$' THEN
    RETURN (btrim(v #>> '{}'))::int;
  END IF;
  RETURN NULL;
END;
$$;

-- A jsonb value as a number, or NULL when it is not unambiguously one.
CREATE OR REPLACE FUNCTION public._wk_num(v jsonb)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF v IS NULL OR jsonb_typeof(v) = 'null' THEN RETURN NULL; END IF;
  IF jsonb_typeof(v) = 'number' THEN RETURN v::numeric; END IF;
  IF jsonb_typeof(v) = 'string' AND btrim(v #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN
    RETURN (btrim(v #>> '{}'))::numeric;
  END IF;
  RETURN NULL;
END;
$$;

-- int → jsonb number, or JSON null.
CREATE OR REPLACE FUNCTION public._wk_jint(v int)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN v IS NULL THEN 'null'::jsonb ELSE to_jsonb(v) END $$;

CREATE OR REPLACE FUNCTION public._wk_jnum(v numeric)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN v IS NULL THEN 'null'::jsonb ELSE to_jsonb(v) END $$;

-- ── 2. Canonicalization ─────────────────────────────────────────────────────

-- One exercise element, in canonical form.
--
-- `p_position` is the element's index in the array — the ordering authority —
-- and is also the tie-break for a minted identity, so two same-named exercises
-- in one day never collapse into one instance.
CREATE OR REPLACE FUNCTION public.canonical_exercise_prescription(
  e jsonb, p_position int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_name     text;
  v_instance text;
  v_slug     text;
  v_details  jsonb;
  d          jsonb;
  i          int := 0;
  out_det    jsonb := '[]'::jsonb;
BEGIN
  IF e IS NULL OR jsonb_typeof(e) <> 'object' THEN RETURN NULL; END IF;

  v_name := btrim(coalesce(e->>'name', ''));
  IF v_name = '' THEN RETURN NULL; END IF;

  -- Identity: whatever the row already carries wins, so an id that has been
  -- handed out and logged against is never re-minted. `id` is accepted as the
  -- legacy spelling the Program Intelligence Engine used.
  v_instance := nullif(btrim(coalesce(
                  e->>'exercise_instance_id', e->>'id', '')), '');
  IF v_instance IS NULL THEN
    v_slug := btrim(regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g'), '-');
    IF v_slug = '' THEN v_slug := 'ex'; END IF;
    v_instance := 'ex-' || v_slug || '-' || p_position;
  END IF;

  -- Per-set detail, when present, keeps its own identities.
  v_details := e->'set_details';
  IF v_details IS NOT NULL AND jsonb_typeof(v_details) = 'array' THEN
    FOR d IN SELECT * FROM jsonb_array_elements(v_details) LOOP
      out_det := out_det || jsonb_build_object(
        'id', coalesce(nullif(btrim(coalesce(d->>'id','')), ''),
                       v_instance || ':s' || (i + 1)),
        'set_number', coalesce(public._wk_int(d->'set_number'), i + 1),
        'reps', public._wk_jint(public._wk_int(d->'reps')),
        'weight_kg', public._wk_jnum(coalesce(
            public._wk_num(d->'weight_kg'), public._wk_num(d->'weight'))),
        'rest_seconds', public._wk_jint(coalesce(
            public._wk_int(d->'rest_seconds'), public._wk_int(d->'rest'))),
        'rpe', public._wk_jnum(public._wk_num(d->'rpe')),
        'tempo', coalesce(d->'tempo', 'null'::jsonb),
        'duration_seconds', public._wk_jint(coalesce(
            public._wk_int(d->'duration_seconds'), public._wk_int(d->'duration'))),
        'notes', coalesce(d->'notes', 'null'::jsonb));
      i := i + 1;
    END LOOP;
  END IF;

  RETURN
    -- Descriptive/library fields and superset/circuit flags are carried through
    -- untouched; the canonical keys below then overwrite their legacy spellings.
    (e - 'id' - 'rest' - 'weight' - 'duration' - 'set_details')
    || jsonb_build_object(
      'exercise_instance_id', v_instance,
      'name', v_name,
      'position', p_position,
      'sets', public._wk_jint(coalesce(
          public._wk_int(e->'sets'),
          CASE WHEN out_det <> '[]'::jsonb
               THEN jsonb_array_length(out_det) END)),
      'reps', public._wk_jint(public._wk_int(e->'reps')),
      -- Absent load is NULL, never 0.
      'weight_kg', public._wk_jnum(coalesce(
          public._wk_num(e->'weight_kg'), public._wk_num(e->'weight'))),
      'rest_seconds', public._wk_jint(coalesce(
          public._wk_int(e->'rest_seconds'), public._wk_int(e->'rest'))),
      'rpe', public._wk_jnum(public._wk_num(e->'rpe')),
      'tempo', coalesce(e->'tempo', 'null'::jsonb),
      'duration_seconds', public._wk_jint(coalesce(
          public._wk_int(e->'duration_seconds'), public._wk_int(e->'duration'))),
      'notes', coalesce(e->'notes', 'null'::jsonb))
    || CASE WHEN out_det = '[]'::jsonb THEN '{}'::jsonb
            ELSE jsonb_build_object('set_details', out_det) END;
END;
$$;

COMMENT ON FUNCTION public.canonical_exercise_prescription(jsonb, int) IS
  'One exercise prescription in the canonical contract of '
  'docs/WORKOUT_DOMAIN_CONTRACT.md §3. Returns NULL when the element cannot be '
  'canonicalised (no name), which the CHECK then rejects.';

-- A whole `exercises` array, canonicalised.
CREATE OR REPLACE FUNCTION public.canonical_exercise_prescriptions(arr jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN arr IS NULL THEN '[]'::jsonb
    WHEN jsonb_typeof(arr) <> 'array' THEN arr   -- left alone; CHECK rejects it
    ELSE coalesce(
      (SELECT jsonb_agg(coalesce(
                public.canonical_exercise_prescription(e.value, (e.ordinality - 1)::int),
                e.value)                          -- un-canonicalisable: preserved
              ORDER BY e.ordinality)
       FROM jsonb_array_elements(arr) WITH ORDINALITY e(value, ordinality)),
      '[]'::jsonb)
  END;
$$;

-- ── 3. Validation ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_canonical_exercise_prescription(arr jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE e jsonb;
BEGIN
  IF arr IS NULL THEN RETURN true; END IF;
  IF jsonb_typeof(arr) <> 'array' THEN RETURN false; END IF;

  FOR e IN SELECT * FROM jsonb_array_elements(arr) LOOP
    IF jsonb_typeof(e) <> 'object' THEN RETURN false; END IF;

    -- Identity and name are required and non-empty.
    IF coalesce(btrim(e->>'exercise_instance_id'), '') = '' THEN RETURN false; END IF;
    IF coalesce(btrim(e->>'name'), '') = '' THEN RETURN false; END IF;

    -- sets/reps are required whole numbers of the canonical JSON type. A
    -- string here is a violation, not a dialect: the canonicalizing trigger has
    -- already converted every string that was unambiguously a number, so what
    -- is left ("8-12", "", "ten") genuinely has no single value.
    IF jsonb_typeof(e->'sets') <> 'number' OR (e->>'sets')::numeric < 1
       OR (e->>'sets')::numeric <> trunc((e->>'sets')::numeric) THEN
      RETURN false;
    END IF;
    IF jsonb_typeof(e->'reps') <> 'number' OR (e->>'reps')::numeric < 0
       OR (e->>'reps')::numeric <> trunc((e->>'reps')::numeric) THEN
      RETURN false;
    END IF;

    -- weight_kg must be PRESENT. Its value may be null (no prescribed load) or
    -- a non-negative number. Requiring the key is what stops a writer omitting
    -- load and a reader inventing 0 for it.
    IF NOT (e ? 'weight_kg') THEN RETURN false; END IF;
    IF jsonb_typeof(e->'weight_kg') NOT IN ('null', 'number') THEN RETURN false; END IF;
    IF jsonb_typeof(e->'weight_kg') = 'number'
       AND (e->>'weight_kg')::numeric < 0 THEN RETURN false; END IF;

    IF jsonb_typeof(coalesce(e->'rest_seconds','null'::jsonb))
         NOT IN ('null','number') THEN RETURN false; END IF;
    IF jsonb_typeof(coalesce(e->'rpe','null'::jsonb))
         NOT IN ('null','number') THEN RETURN false; END IF;
    IF jsonb_typeof(coalesce(e->'tempo','null'::jsonb))
         NOT IN ('null','string') THEN RETURN false; END IF;

    -- A legacy spelling surviving into a stored row means the trigger was
    -- bypassed; treat it as non-canonical rather than tolerate two keys.
    IF e ? 'rest' OR e ? 'weight' THEN RETURN false; END IF;
  END LOOP;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.is_canonical_exercise_prescription(jsonb) IS
  'True when every element satisfies the canonical exercise-prescription '
  'contract. Backs the CHECK on program_workouts.exercises.';

-- ── 4. The boundary: canonicalize on every write ────────────────────────────

CREATE OR REPLACE FUNCTION public.program_workouts_canonicalize()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.exercises := public.canonical_exercise_prescriptions(NEW.exercises);

  -- `day_of_week` is a label, and it was being written two ways: the app and
  -- the generators write 'Monday'…'Sunday', the seed wrote '1'…'7'. The client
  -- matches today's name against it, so a numeric row could never be today's
  -- workout. Verified live: the QA seed program stores "1","2","4","5".
  IF NEW.day_of_week ~ '^[1-7]$' THEN
    NEW.day_of_week := (ARRAY['Monday','Tuesday','Wednesday','Thursday',
                              'Friday','Saturday','Sunday'])[NEW.day_of_week::int];
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_program_workouts_canonicalize ON public.program_workouts;
CREATE TRIGGER trg_program_workouts_canonicalize
  BEFORE INSERT OR UPDATE ON public.program_workouts
  FOR EACH ROW EXECUTE FUNCTION public.program_workouts_canonicalize();

COMMENT ON TRIGGER trg_program_workouts_canonicalize ON public.program_workouts IS
  'Normalises every write to the canonical prescription contract: mints missing '
  'exercise_instance_ids, translates the legacy rest/weight/id spellings, '
  'converts unambiguous numeric strings, derives position, and makes absent '
  'load an explicit null. Runs BEFORE the CHECK, so a legacy writer produces a '
  'canonical row and only genuinely ambiguous data is rejected.';

-- ── 5. Migrate existing rows ────────────────────────────────────────────────

UPDATE public.program_workouts
   SET exercises = public.canonical_exercise_prescriptions(exercises)
 WHERE exercises IS NOT NULL;

UPDATE public.program_workouts
   SET day_of_week = (ARRAY['Monday','Tuesday','Wednesday','Thursday',
                            'Friday','Saturday','Sunday'])[day_of_week::int]
 WHERE day_of_week ~ '^[1-7]$';

-- Any row that survives canonicalization still non-canonical carries data no
-- writer can have meant — it is reported here rather than silently dropped, and
-- the CHECK below is added NOT VALID so it constrains new writes without
-- failing the migration on historical rows a human must look at.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.program_workouts
   WHERE NOT public.is_canonical_exercise_prescription(exercises);
  IF n > 0 THEN
    RAISE WARNING 'migration 119: % program_workouts row(s) could not be '
      'canonicalised and are excluded from the CHECK until repaired. '
      'Find them with: SELECT id, program_id, title FROM program_workouts '
      'WHERE NOT public.is_canonical_exercise_prescription(exercises);', n;
  END IF;
END;
$$;

ALTER TABLE public.program_workouts
  DROP CONSTRAINT IF EXISTS program_workouts_exercises_canonical;
ALTER TABLE public.program_workouts
  ADD CONSTRAINT program_workouts_exercises_canonical
  CHECK (public.is_canonical_exercise_prescription(exercises)) NOT VALID;

COMMENT ON COLUMN public.program_workouts.exercises IS
  'Canonical exercise prescriptions — docs/WORKOUT_DOMAIN_CONTRACT.md §3. '
  'Enforced by trg_program_workouts_canonicalize + '
  'program_workouts_exercises_canonical. weight_kg is a required key whose '
  'null means NO PRESCRIBED LOAD; it is never 0-for-unknown.';

-- ── 6. Generators emit the contract ─────────────────────────────────────────

-- Self-guided generator. Same movements, same volume rules — only the emitted
-- shape changes, plus an explicit `weight_kg: null` because this generator has
-- never prescribed load and must say so rather than let a reader invent 0.
CREATE OR REPLACE FUNCTION public._plan_day_exercises(
  focus text, is_home boolean, p_reps int, p_rest int)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'exercise_instance_id',
             'ex-' || btrim(regexp_replace(lower(x.ex), '[^a-z0-9]+', '-', 'g'), '-')
               || '-' || (x.ord - 1),
           'name', x.ex,
           'position', (x.ord - 1)::int,
           'sets', 3,
           'reps', p_reps,
           'weight_kg', null,
           'rest_seconds', p_rest,
           'rpe', null,
           'tempo', null,
           'duration_seconds', null,
           'notes', null
         ) ORDER BY x.ord), '[]'::jsonb)
  FROM unnest(case
    when focus='full_body' and is_home then array['Goblet Squat','Push-Up','Inverted Row','Pike Push-Up','Plank']
    when focus='full_body'             then array['Barbell Squat','Bench Press','Bent-Over Row','Overhead Press','Plank']
    when focus='upper' and is_home     then array['Push-Up','Inverted Row','Pike Push-Up','Band Row','Bicep Curl','Dip']
    when focus='upper'                 then array['Bench Press','Bent-Over Row','Overhead Press','Lat Pulldown','Bicep Curl','Tricep Pushdown']
    when focus='lower' and is_home     then array['Goblet Squat','Single-Leg RDL','Walking Lunge','Glute Bridge','Calf Raise']
    when focus='lower'                 then array['Back Squat','Romanian Deadlift','Leg Press','Leg Curl','Standing Calf Raise']
    when focus='push' and is_home      then array['Push-Up','Pike Push-Up','Decline Push-Up','Lateral Raise','Dip']
    when focus='push'                  then array['Bench Press','Overhead Press','Incline DB Press','Lateral Raise','Tricep Pushdown']
    when focus='pull' and is_home      then array['Pull-Up','Inverted Row','Band Row','Face Pull','Bicep Curl']
    when focus='pull'                  then array['Deadlift','Pull-Up','Bent-Over Row','Face Pull','Bicep Curl']
    when focus='legs' and is_home      then array['Goblet Squat','Single-Leg RDL','Walking Lunge','Glute Bridge','Calf Raise']
    when focus='legs'                  then array['Back Squat','Romanian Deadlift','Leg Press','Leg Curl','Standing Calf Raise']
    else array['Push-Up','Bodyweight Squat','Plank']
  end) WITH ORDINALITY AS x(ex, ord);
$$;

-- ── 7. The engine materializes a prescription, or fails ─────────────────────
--
-- `materialize_program_week` inserted `coalesce(v_result->'selected','[]')`
-- straight into `exercises`. Two problems, both live-verified against QA:
--
--   * `build_workout` emits `{id, name, pattern, score, systemic_fatigue}` —
--     which movements, and nothing about how to train them. Every
--     engine-materialized session therefore reached the client as the codec's
--     defaults: 3 x 10 at 0 kg with 90 s rest. None of those numbers came from
--     the engine, or from a coach.
--   * an empty selection (QA's `exercise_intelligence` is unpopulated, so
--     `selected` comes back `[]`) was written as a workout with no exercises
--     and REPORTED AS SUCCESS — `sessions_created: 4`, four empty days.
--
-- This migration fixes the honesty half and leaves the prescription half open:
--
--   * an empty selection now RAISES. The engine failing to select is a failure
--     to surface, not an empty workout to hand a client.
--   * the selection is written in the canonical contract, structure only, with
--     `weight_kg: null`.
--
-- The structural defaults below (`sets`/`reps`/`rest_seconds`) are taken from
-- the caller's context so they are the caller's numbers, not invented ones, and
-- the contract records that the engine does not yet prescribe them
-- (docs/WORKOUT_DOMAIN_CONTRACT.md §8 gap G-1). LOAD IS NOT INVENTED: whether
-- the deterministic engine should prescribe load, and by what rule, is an open
-- product decision and is deliberately NOT answered here.
CREATE OR REPLACE FUNCTION public.materialize_program_week(
  p_program_id uuid, p_week int, p_context jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_plan jsonb; v_week jsonb; v_split jsonb; v_vol numeric; v_base int;
  i int; v_ctx jsonb; v_result jsonb; v_made int := 0; v_sessions jsonb := '[]'::jsonb;
  v_sets int; v_reps int; v_rest int; v_selected jsonb; v_exercises jsonb;
BEGIN
  SELECT plan INTO v_plan FROM workout_programs WHERE id = p_program_id;
  IF v_plan IS NULL THEN RAISE EXCEPTION 'program has no plan'; END IF;
  SELECT w INTO v_week FROM jsonb_array_elements(v_plan->'weeks') w
   WHERE (w->>'week')::int = p_week;
  IF v_week IS NULL THEN RAISE EXCEPTION 'week % not in plan', p_week; END IF;

  v_split := v_week->'split';
  v_vol   := coalesce((v_week->>'volume_multiplier')::numeric, 1.0);
  v_base  := coalesce((p_context->>'size')::int, 5);

  -- Session structure comes from the caller's context, which is where the
  -- coach's/plan's own numbers live. Absent, it is the plan's, not a guess
  -- dressed up as a prescription.
  v_sets := coalesce(public._wk_int(p_context->'sets'), 3);
  v_reps := coalesce(public._wk_int(p_context->'reps'), 10);
  v_rest := public._wk_int(p_context->'rest_seconds');

  -- Clear any prior materialization of this week.
  DELETE FROM program_workouts WHERE program_id = p_program_id AND week_number = p_week;

  FOR i IN 0 .. jsonb_array_length(v_split) - 1 LOOP
    v_ctx := p_context || jsonb_build_object(
      'size', greatest(2, round(v_base * v_vol)),
      'recovery', coalesce((p_context->>'recovery')::int, 75));
    v_result := public.generate_workout(v_ctx, (p_context->>'subject')::uuid);
    v_selected := coalesce(v_result->'selected', '[]'::jsonb);

    IF jsonb_array_length(v_selected) = 0 THEN
      RAISE EXCEPTION
        'engine selected no exercises for week % session % (program %). '
        'Materialization aborted rather than writing an empty workout. '
        'The usual cause is an unpopulated exercise_intelligence substrate.',
        p_week, coalesce(v_split->>i, i::text), p_program_id;
    END IF;

    SELECT jsonb_agg(jsonb_build_object(
             'exercise_instance_id', gen_random_uuid()::text,
             'exercise_id', s.value->>'id',
             'name', s.value->>'name',
             'position', (s.ordinality - 1)::int,
             'sets', v_sets,
             'reps', v_reps,
             -- The engine does not prescribe load. Saying so explicitly is the
             -- whole point of the contract's nullable weight_kg.
             'weight_kg', null,
             'rest_seconds', public._wk_jint(v_rest),
             'rpe', null,
             'tempo', null,
             'duration_seconds', null,
             'notes', null,
             'movement_pattern', s.value->>'pattern')
           ORDER BY s.ordinality)
      INTO v_exercises
      FROM jsonb_array_elements(v_selected) WITH ORDINALITY s(value, ordinality);

    INSERT INTO program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
    VALUES (p_program_id, p_week,
      (ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])
        [least(i + 1, 7)],
      format('Week %s · %s', p_week, v_split->>i),
      v_exercises, i);
    v_made := v_made + 1;
    v_sessions := v_sessions || jsonb_build_object(
      'session', v_split->>i, 'trace_id', v_result->'trace_id',
      'exercises', jsonb_array_length(v_exercises));
  END LOOP;

  RETURN jsonb_build_object('week', p_week, 'sessions_created', v_made,
                            'sessions', v_sessions);
END;
$$;

GRANT EXECUTE ON FUNCTION public.materialize_program_week(uuid, int, jsonb) TO authenticated;

-- ── 8. Grants ───────────────────────────────────────────────────────────────
--
-- Validation/canonicalization helpers touch no table and are IMMUTABLE, so they
-- introduce no privileged read path and do not widen the Phase 1 boundary.
REVOKE ALL ON FUNCTION public._wk_int(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._wk_num(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._wk_jint(int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._wk_jnum(numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.canonical_exercise_prescription(jsonb, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.canonical_exercise_prescriptions(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_canonical_exercise_prescription(jsonb) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public._wk_int(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public._wk_num(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public._wk_jint(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public._wk_jnum(numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.canonical_exercise_prescription(jsonb, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.canonical_exercise_prescriptions(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_canonical_exercise_prescription(jsonb) TO authenticated;
