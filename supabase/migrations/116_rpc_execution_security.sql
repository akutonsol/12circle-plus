-- 116_rpc_execution_security.sql
--
-- PHASE 1D — SECURITY DEFINER function privilege review.
--
-- ── THE STATE BEFORE THIS MIGRATION (measured on QA) ────────────────────────
--   100 functions in schema public
--    86 SECURITY DEFINER
--    73 SECURITY DEFINER with NO pinned search_path
--    98 executable by `anon` -- i.e. by the whole internet, because the anon key
--       is compiled into the published client build
--    84 both SECURITY DEFINER and anon-executable
--
-- Postgres grants EXECUTE to PUBLIC on every new function, and nothing in
-- migrations 001-115 ever took it back. That is the root cause of the whole
-- class, not a per-function oversight.
--
-- Concretely, before this migration an anonymous caller could:
--   * insert_notification(<any user>, ...) -- inject an arbitrary titled and
--     bodied notification into any user's feed (a clean phishing surface)
--   * generate_workout(ctx, <any subject>) -- write a decision_traces row
--     attributed to somebody else, forging engine provenance
--   * create_weekly_review(<any subject>, ...) -- create a communications draft
--     against a stranger
--   * record_prediction(<any subject>, ...) -- write a predictions row for them
--   * predict_client(<any subject>, ...) / assemble_weekly_review(...) -- read a
--     stranger's adherence, recovery, pain reports and goal trajectory
--   * resolve_exercise_media(ex, <any viewer>) -- learn who somebody's coach is
--     and read that coach's private note, voice note and video for them
--   * ai_adjust_nutrition(<any user>) -- rewrite a stranger's macro targets
--   * mie_upsert_node/edge, rebuild_*, seed_exercise -- rewrite the movement
--     graph and certified exercise intelligence the engine plans from
--
-- ── THE APPROACH ────────────────────────────────────────────────────────────
-- Not a blanket revoke. Every function is classified and treated on its class:
--
--   A public/internal helper   -> no client EXECUTE; reached through triggers,
--                                 policies or other functions
--   B authenticated user fn    -> EXECUTE to authenticated; derives its subject
--                                 from auth.uid(), never from a parameter
--   C coach-authorized fn      -> EXECUTE to authenticated; proves the caller is
--                                 the subject, their active coach, or an admin
--   D service-role / engine fn -> no client EXECUTE at all
--   E admin / content-editor   -> EXECUTE to authenticated; self-guards on
--                                 is_admin() / is_content_editor()
--
-- The deterministic engine is NOT broken: service_role and postgres keep every
-- grant, and every guard added below is written `auth.uid() IS NULL OR ...`, so
-- the internal path (pg_cron, edge functions, the API's service client,
-- migrations) is unaffected by construction.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
--   -- plus DROP the four *_engine wrappers and rename the originals back.

-- ---------------------------------------------------------------------------
-- 1. Pin search_path on every SECURITY DEFINER function that lacks one.
--
-- A definer function without a pinned search_path resolves unqualified names
-- through the CALLER's search_path. A caller who can create objects in a schema
-- earlier on that path can shadow a table or operator and have it executed with
-- the definer's rights. Done as ALTER FUNCTION so no function body is touched.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  f record;
  n int := 0;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE ns.nspname = 'public'
       AND p.prosecdef
       AND NOT EXISTS (
         SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', f.sig);
    n := n + 1;
  END LOOP;
  RAISE NOTICE '116: pinned search_path on % SECURITY DEFINER functions', n;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Authorization predicates.
--
-- can_act_for() is the answer to "is this caller allowed to operate on this
-- subject?" -- the question the intelligence functions were not asking. It is
-- the same shape as the read policies migration 100 installed, so an RPC and a
-- direct table read now agree on who may see a given member's data.
--
-- The `auth.uid() IS NULL` arm is the internal/engine path and is load-bearing:
-- pg_cron, the edge functions and the NestJS API all call in as service_role,
-- which has no JWT subject.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_act_for(subject uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (SELECT auth.uid()) IS NULL            -- service_role / engine
      OR subject IS NULL                        -- unscoped call, subject defaulted
      OR subject = (SELECT auth.uid())          -- the member themselves
      OR public.is_active_coach_of(subject)     -- their active coach
      OR public.is_admin();
$$;

CREATE OR REPLACE FUNCTION public.can_act_on_program(program uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (SELECT auth.uid()) IS NULL
      OR program IS NULL
      OR public.is_admin()
      OR EXISTS (SELECT 1 FROM public.workout_programs p
                  WHERE p.id = program AND p.coach_id = (SELECT auth.uid()))
      OR EXISTS (SELECT 1 FROM public.workout_program_assignments a
                  WHERE a.program_id = program AND a.client_id = (SELECT auth.uid()))
      OR EXISTS (SELECT 1 FROM public.workout_program_assignments a
                  WHERE a.program_id = program AND public.is_active_coach_of(a.client_id));
$$;

REVOKE ALL ON FUNCTION public.can_act_for(uuid)        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_act_on_program(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_act_for(uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_act_on_program(uuid) TO authenticated;

COMMENT ON FUNCTION public.can_act_for(uuid) IS
  'Authorization predicate for subject-scoped RPCs: the member themselves, their '
  'active coach, an admin, or the internal engine (auth.uid() IS NULL). Any '
  'SECURITY DEFINER function that accepts a subject UUID must consult this '
  'rather than trusting the parameter.';

-- ---------------------------------------------------------------------------
-- 3. Short subject-scoped functions: guard written into the body.
--
-- Parameter DEFAULTs are reproduced exactly. CREATE OR REPLACE cannot drop a
-- default from an existing function, and dropping one would silently change
-- every two-argument call site into an error.
-- ---------------------------------------------------------------------------

-- resolve_exercise_media took a VIEWER id and answered for that viewer, so any
-- caller could ask "who coaches this person, and what did that coach record
-- privately for them?". The viewer is now always the caller. The parameter is
-- kept so the Flutter call site and the PostgREST signature do not change, but
-- it is only honoured for a caller entitled to act for that viewer.
CREATE OR REPLACE FUNCTION public.resolve_exercise_media(p_exercise_id uuid, p_viewer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_viewer uuid := COALESCE(p_viewer_id, (SELECT auth.uid()));
BEGIN
  IF NOT public.can_act_for(v_viewer) THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;
  RETURN public.resolve_exercise_media_for(p_exercise_id, v_viewer);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_exercise_media_for(p_exercise_id uuid, p_viewer_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE((
    SELECT jsonb_build_object(
      'has_coach_overlay', true,
      'coach_id', m.coach_id,
      'coach_name', up.first_name,
      'note', m.note,
      'focus', to_jsonb(COALESCE(m.focus, '{}')),
      'video_ref', m.video_ref,
      'voice_url', CASE WHEN m.voice_expires_at IS NULL OR m.voice_expires_at > now()
                        THEN m.voice_url END,
      'voice_duration_ms', CASE WHEN m.voice_expires_at IS NULL OR m.voice_expires_at > now()
                                THEN m.voice_duration_ms END,
      'updated_at', m.updated_at)
    FROM public.coach_client_relationships r
    JOIN public.coach_exercise_media m ON m.coach_id = r.coach_id AND m.exercise_id = p_exercise_id
    JOIN public.user_profiles up ON up.id = m.coach_id
    WHERE r.client_id = p_viewer_id AND r.status = 'active'
    ORDER BY r.activated_at DESC NULLS LAST
    LIMIT 1),
    jsonb_build_object('has_coach_overlay', false));
$$;

-- generate_workout wrote a decision_traces row whose subject_id came straight
-- from the parameter, so anybody could plant engine provenance against anybody.
CREATE OR REPLACE FUNCTION public.generate_workout(p_context jsonb, p_subject uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  plan jsonb;
  v_id uuid;
  v_subject uuid := COALESCE(p_subject, (SELECT auth.uid()));
BEGIN
  IF NOT public.can_act_for(v_subject) THEN
    RAISE EXCEPTION 'not authorized to generate for this subject' USING ERRCODE = '42501';
  END IF;
  plan := public.build_workout(p_context);
  INSERT INTO decision_traces(
    subject_id, created_by, engine_version, rules_version, scoring_version, graph_version,
    context, result, trace, rules_triggered)
  VALUES (
    v_subject, (SELECT auth.uid()),
    '3.0.0', '1.0.0', '1.0.0', '1.0.0',
    p_context,
    plan - 'trace' - 'rules_triggered',
    COALESCE(plan->'trace', '[]'::jsonb),
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(plan->'rules_triggered', '[]'::jsonb))))
  RETURNING id INTO v_id;
  RETURN plan || jsonb_build_object('trace_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_weekly_review(p_subject uuid, p_program uuid, p_week integer)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_brief jsonb;
  v_id uuid;
  v_coach uuid;
BEGIN
  IF NOT public.can_act_for(p_subject) THEN
    RAISE EXCEPTION 'not authorized for this subject' USING ERRCODE = '42501';
  END IF;
  v_brief := public.assemble_weekly_review(p_subject, p_program, p_week);
  IF v_brief->>'status' <> 'ok' THEN RETURN v_brief; END IF;
  SELECT coach_id INTO v_coach FROM workout_programs WHERE id = p_program;
  INSERT INTO communications(subject_id, coach_id, program_id, type, brief, source_refs, status)
  VALUES (p_subject, COALESCE(v_coach, (SELECT auth.uid())), p_program, 'weekly_review',
          v_brief, v_brief->'source_refs', 'draft')
  RETURNING id INTO v_id;
  RETURN v_brief || jsonb_build_object('communication_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.record_prediction(p_subject uuid, p_program uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  pred jsonb;
  v_id uuid;
BEGIN
  IF NOT public.can_act_for(p_subject) THEN
    RAISE EXCEPTION 'not authorized for this subject' USING ERRCODE = '42501';
  END IF;
  pred := public.predict_client(p_subject, p_program);
  IF pred->>'status' <> 'ok' THEN RETURN pred; END IF;
  INSERT INTO predictions(subject_id, program_id, prediction, confidence, engine_version)
  VALUES (p_subject, (pred->>'program_id')::uuid, pred,
    (pred#>>'{goal,confidence}')::int, pred->>'engine_version')
  RETURNING id INTO v_id;
  RETURN pred || jsonb_build_object('prediction_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.snapshot_program_version(p_program_id uuid, p_reason text)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_next int;
  v_strat jsonb;
  v_plan jsonb;
BEGIN
  IF NOT public.can_act_on_program(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program' USING ERRCODE = '42501';
  END IF;
  SELECT strategy, plan INTO v_strat, v_plan FROM workout_programs WHERE id = p_program_id;
  SELECT COALESCE(max(version), 0) + 1 INTO v_next FROM program_versions WHERE program_id = p_program_id;
  INSERT INTO program_versions(program_id, version, strategy, plan, reason, created_by)
  VALUES (p_program_id, v_next, v_strat, v_plan, p_reason, (SELECT auth.uid()));
  UPDATE workout_programs SET program_version = v_next WHERE id = p_program_id;
  RETURN v_next;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Long engine functions: guard by delegation.
--
-- These bodies are hundreds of lines of deterministic planning logic. Retyping
-- them into a migration to insert three lines at the top is how transcription
-- bugs get into an engine, so instead each is renamed to <name>_engine, has its
-- client EXECUTE removed, and keeps its public name as a thin authorized
-- wrapper. The engine logic is byte-identical to what was verified before.
--
-- If a future migration replaces one of these by its PUBLIC name it will
-- replace the WRAPPER and silently drop the guard. The regression suite
-- (supabase/tests/security) asserts each guard, which is what catches that.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('predict_client',          'predict_client(uuid,uuid)'),
      ('assemble_weekly_review',  'assemble_weekly_review(uuid,uuid,integer)'),
      ('evaluate_week',           'evaluate_week(uuid,integer)'),
      ('materialize_program_week','materialize_program_week(uuid,integer,jsonb)'),
      ('regenerate_program',      'regenerate_program(uuid,integer,boolean)')
    ) AS t(nm, sig)
  LOOP
    -- Idempotent: only rename the first time, and only if the *_engine name is free.
    IF to_regprocedure('public.' || r.sig) IS NOT NULL
       AND to_regprocedure('public.' || replace(r.sig, r.nm || '(', r.nm || '_engine(')) IS NULL THEN
      EXECUTE format('ALTER FUNCTION public.%s RENAME TO %I', r.sig, r.nm || '_engine');
      RAISE NOTICE '116: public.% renamed to %_engine', r.nm, r.nm;
    END IF;
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.predict_client_engine(uuid, uuid)                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.assemble_weekly_review_engine(uuid, uuid, integer)   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.evaluate_week_engine(uuid, integer)                  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.materialize_program_week_engine(uuid, integer, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.regenerate_program_engine(uuid, integer, boolean)    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.predict_client(p_subject uuid, p_program uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_for(p_subject) THEN
    RAISE EXCEPTION 'not authorized for this subject' USING ERRCODE = '42501';
  END IF;
  RETURN public.predict_client_engine(p_subject, p_program);
END;
$$;

CREATE OR REPLACE FUNCTION public.assemble_weekly_review(p_subject uuid, p_program uuid, p_week integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_for(p_subject) THEN
    RAISE EXCEPTION 'not authorized for this subject' USING ERRCODE = '42501';
  END IF;
  RETURN public.assemble_weekly_review_engine(p_subject, p_program, p_week);
END;
$$;

CREATE OR REPLACE FUNCTION public.evaluate_week(p_program_id uuid, p_week integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_on_program(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program' USING ERRCODE = '42501';
  END IF;
  RETURN public.evaluate_week_engine(p_program_id, p_week);
END;
$$;

CREATE OR REPLACE FUNCTION public.materialize_program_week(p_program_id uuid, p_week integer, p_context jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_on_program(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program' USING ERRCODE = '42501';
  END IF;
  RETURN public.materialize_program_week_engine(p_program_id, p_week, p_context);
END;
$$;

CREATE OR REPLACE FUNCTION public.regenerate_program(p_program_id uuid, p_week integer, p_approved boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.can_act_on_program(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program' USING ERRCODE = '42501';
  END IF;
  RETURN public.regenerate_program_engine(p_program_id, p_week, p_approved);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Moderation dashboards: gate on is_content_editor().
--
-- These read the engine's internal state -- confidence scores, review queues,
-- decision analytics, the movement graph's shape. Phase 1E's rule is that
-- deterministic engine inputs are not exposed to arbitrary clients, and every
-- Flutter call site for these is behind the admin / content-manager screens.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.require_content_editor()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NOT NULL AND NOT public.is_content_editor() THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.require_content_editor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_content_editor() TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Privileges.
--
-- Take EXECUTE back from PUBLIC (which is where anon's access came from) across
-- the whole schema, then hand it back only where a signed-in client genuinely
-- calls the function. service_role and postgres are untouched -- that is the
-- engine's execution path and it must keep working.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM authenticated;

-- Future functions inherit the same posture instead of re-opening the hole.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;

DO $$
DECLARE
  fn text;
  -- Class B/C/E: everything a signed-in client legitimately calls, plus the
  -- predicates that RLS policies and views evaluate as the caller.
  allowed constant text[] := ARRAY[
    -- policy / view predicates (must be callable or RLS itself fails)
    'is_active_coach_of', 'is_coach_profile', 'is_admin', 'is_content_editor',
    'is_team_lead_of', 'hosts_event_for', 'shares_conversation_with',
    'exercise_readable', 'exercise_writable',
    'can_act_for', 'can_act_on_program', 'require_content_editor',
    -- B: self-scoped member functions
    'active_membership', 'client_plan', 'coach_plan_tier',
    'award_points', 'penalize_points',
    'generate_client_plan', 'deactivate_self_generated_plan',
    'leaderboard_global', 'leaderboard_coach',
    'marketplace_coaches', 'coach_active_client_counts',
    -- B: pure/deterministic helpers with no subject and no writes
    'build_workout', 'rank_exercises', 'score_exercise', 'generate_warmup',
    'validate_week', 'plan_program', 'movement_graph', 'derive_parq_risk',
    'exercise_certification', 'resolve_exercise_media', 'project_base_url',
    -- C: subject/program-scoped, now guarded by can_act_for / can_act_on_program
    'generate_workout', 'predict_client', 'record_prediction',
    'assemble_weekly_review', 'create_weekly_review',
    'evaluate_week', 'materialize_program_week', 'regenerate_program',
    'snapshot_program_version', 'coach_client_ai_signals',
    'send_communication', 'update_communication',
    -- E: admin / content-editor, each self-guarding
    'admin_platform_stats', 'admin_recent_users', 'admin_set_user_role',
    'review_exercise_content', 'review_intelligence', 'review_attribute',
    'update_exercise_media', 'finalize_intelligence',
    'rebuild_exercise_intelligence', 'rebuild_movement_graph', 'seed_warmup_library',
    'sync_exercise_relations',
    'intelligence_review_queue', 'intelligence_stats', 'intelligence_low_confidence',
    'attribute_review_state', 'certification_summary', 'exercise_content_stats',
    'decision_analytics', 'movement_graph_stats'
  ];
  sig text;
  granted int := 0;
  found_any boolean;
BEGIN
  FOREACH fn IN ARRAY allowed LOOP
    found_any := false;
    -- Grant every overload of the name; a signature drifting is not a reason to
    -- silently leave an app call site without EXECUTE.
    FOR sig IN
      SELECT p.oid::regprocedure::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = fn
    LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', sig);
      granted := granted + 1;
      found_any := true;
    END LOOP;
    IF NOT found_any THEN
      RAISE EXCEPTION '116: allowlisted function public.% does not exist -- fix the list', fn;
    END IF;
  END LOOP;
  RAISE NOTICE '116: granted EXECUTE to authenticated on % allowlisted functions', granted;
END $$;

COMMENT ON SCHEMA public IS
  'Application schema. Views here are read projections: authenticated holds '
  'SELECT only (migration 112). Functions default to NO client EXECUTE '
  '(migration 116): a new RPC must add itself to the allowlist there and say '
  'which class it is, and any SECURITY DEFINER function that accepts a subject '
  'UUID must check public.can_act_for() rather than trust the parameter.';
