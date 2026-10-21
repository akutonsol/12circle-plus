-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 183. Restores the empty-selection guard that migration 119
-- introduced and migration 124 discarded.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["183"]; environments.qa.applied_through is "181".
--
-- WHY THIS FUNCTION AND NOT THE WRAPPER. Verified from the live replay catalog,
-- not assumed: the INSERT that persists a program week lives in
-- materialize_program_week_engine (lines 31-35 of its catalog definition):
--     insert into program_workouts(program_id, week_number, day_of_week, title,
--                                  exercises, sort_order)
--     values (..., coalesce(v_result->'selected', '[]'::jsonb), i);
-- and v_made increments unconditionally, so an empty selection is written AND
-- reported as `sessions_created`. Migration 124's public wrapper only checks
-- can_act_on_program and delegates. Guarding the wrapper would leave the
-- persistence path reachable by any other caller of the engine; guarding the
-- engine puts the invariant at the write itself.
--
-- WHAT WAS LOST AND WHAT WAS NOT -- scoped precisely so this change stays minimal:
--   * 119's prescription canonicalization is NOT lost. 119:265-284 implemented it
--     as the BEFORE INSERT OR UPDATE trigger trg_program_workouts_canonicalize ->
--     canonical_exercise_prescriptions(NEW.exercises), which is still live and
--     fires on this very INSERT. This migration does NOT re-add 119's in-body
--     sets/reps/rest logic, because the trigger already does that work.
--   * 119's empty-selection guard IS lost: it existed only in the function body.
--     Verified: canonical_exercise_prescriptions('[]'::jsonb) returns '[]' without
--     raising, so the trigger does not guard emptiness.
--
-- BUILT FROM THE CURRENT CATALOG BODY, not from 119. The live definition was
-- captured with pg_get_functiondef and three edits applied: declare v_selected,
-- assign-and-guard after generate_workout, and have the INSERT use v_selected so
-- the expression is evaluated once. Signature, RETURNS, LANGUAGE,
-- SECURITY DEFINER and the search_path pin are preserved exactly as the catalog
-- reports them. No authorization behaviour is touched. PD-A02 is not involved.
--
-- ATOMIC WITH its manifest declaration in supabase/expected_applied.json. The
-- manifest guard fails rule 5 for a declaration without a file and rule 7 for a
-- file without a declaration, so the two must be reviewed and applied together.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.materialize_program_week_engine(p_program_id uuid, p_week integer, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_plan jsonb; v_week jsonb; v_split jsonb; v_vol numeric; v_base int;
  i int; v_ctx jsonb; v_result jsonb; v_made int := 0; v_sessions jsonb := '[]'::jsonb;
  v_selected jsonb;   -- restored with the guard below (119 declared this too)
begin
  select plan into v_plan from workout_programs where id = p_program_id;
  if v_plan is null then raise exception 'program has no plan'; end if;
  select w into v_week from jsonb_array_elements(v_plan->'weeks') w
    where (w->>'week')::int = p_week;
  if v_week is null then raise exception 'week % not in plan', p_week; end if;

  v_split := v_week->'split';
  v_vol := coalesce((v_week->>'volume_multiplier')::numeric, 1.0);
  v_base := coalesce((p_context->>'size')::int, 5);

  -- Clear any prior materialization of this week.
  delete from program_workouts where program_id = p_program_id and week_number = p_week;

  for i in 0 .. jsonb_array_length(v_split) - 1 loop
    -- Per-session context: scale target size by the week's volume multiplier.
    v_ctx := p_context || jsonb_build_object(
      'size', greatest(2, round(v_base * v_vol)),
      'recovery', coalesce((p_context->>'recovery')::int, 75));
    v_result := public.generate_workout(v_ctx, (p_context->>'subject')::uuid);
    v_selected := coalesce(v_result->'selected', '[]'::jsonb);

    -- RESTORED from migration 119:436-444, which migration 124 discarded when it
    -- replaced the public body with a wrapper over this (pre-119) engine. Message
    -- text and arguments are 119's, byte for byte.
    if jsonb_array_length(v_selected) = 0 then
      raise exception
        'engine selected no exercises for week % session % (program %). '
        'Materialization aborted rather than writing an empty workout. '
        'The usual cause is an unpopulated exercise_intelligence substrate.',
        p_week, coalesce(v_split->>i, i::text), p_program_id;
    end if;


    insert into program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
    values (p_program_id, p_week,
      lower(to_char(now(),'day')),  -- placeholder day; coach can reorder
      format('Week %s · %s', p_week, v_split->>i),
      v_selected, i);
    v_made := v_made + 1;
    v_sessions := v_sessions || jsonb_build_object('session', v_split->>i, 'trace_id', v_result->'trace_id');
  end loop;

  return jsonb_build_object('week', p_week, 'sessions_created', v_made, 'sessions', v_sessions);
end;
$function$;
