-- 117_rls_intelligence_substrate.sql
--
-- PHASE 1E — row level security across the intelligence / engine substrate.
--
-- ── WHAT WAS AUDITED ────────────────────────────────────────────────────────
-- ai_*, exercise_* intelligence tables, decision_traces, predictions,
-- program_versions, weekly_feedback, communications, movement_nodes,
-- movement_edges, exercise_intelligence, intelligence_attribute_reviews,
-- workout_programs, program_workouts, user_scores, score_events, score_cycles.
--
-- ── WHAT WAS ALREADY CORRECT (asserted, not changed) ────────────────────────
-- decision_traces, predictions, program_versions, communications,
-- intelligence_attribute_reviews and exercise_content_versions each carry a
-- SELECT policy and NO write policy at all. Under RLS "no policy" means deny, so
-- a client already cannot rewrite a decision trace, a prediction, a program
-- version or an audit row -- the engine writes them through SECURITY DEFINER
-- functions and service_role. The regression suite pins that, because adding a
-- careless FOR ALL policy later would open all of it in one line.
--
-- ── WHAT WAS WRONG ──────────────────────────────────────────────────────────
--  1. ai_conversations' only policy had no TO clause, so it applied to PUBLIC --
--     the same class migration 100 set out to close, missed because 100 audited
--     policies that existed on the tables it was looking at. Not exploitable on
--     its own (the predicate is user_id = auth.uid() and anon's uid is NULL),
--     but it is an anon-reachable policy on AI conversation content and it must
--     not be one bad predicate away from mattering.
--
--  2. Four blanket USING (true) SELECT policies exposed deterministic-engine
--     substrate to every authenticated account:
--       exercise_intelligence  -- certified intelligence + confidence/provenance
--       movement_nodes         -- the movement graph the planner traverses
--       movement_edges         --   "
--       user_scores            -- every member's lifetime score, level and rank
--     None of the first three has a single direct read anywhere in apps/ -- the
--     client reaches the graph through movement_graph(), which is SECURITY
--     DEFINER and survives this change untouched.
--
--  3. workout_programs and program_workouts were world-readable to any
--     authenticated account (`all read programs`, `all read program workouts`,
--     both USING (true)). Every coach's programming -- their actual product --
--     was readable by any signed-up account, and program_workouts is a
--     deterministic-engine output (materialize_program_week writes it).
--
--  4. weekly_feedback's FOR ALL policy let the subject DELETE their own feedback
--     rows. weekly_feedback is the engine's INPUT: evaluate_week() reads it and
--     regenerate_program() acts on it. Deleting it silently rewrites the
--     evidence a progression decision was made on.
--
-- ── WHAT IS DELIBERATELY LEFT OPEN ──────────────────────────────────────────
-- exercises / exercise_videos and the exercise_* child tables stay readable to
-- every authenticated user (exercise_readable(), or USING (true) for videos).
-- That is the shared exercise library -- it is product content, not engine
-- state, and every exercise screen depends on it.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- Each section below re-creates a named policy; to revert, re-create the prior
-- policy with USING (true). The prior definitions are quoted inline.

-- ---------------------------------------------------------------------------
-- 1. ai_conversations -- close the PUBLIC policy.
--    Prior: CREATE POLICY "Users see own AI conversations" ON ai_conversations
--             FOR ALL USING (user_id = auth.uid());     -- no TO clause
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users see own AI conversations" ON public.ai_conversations;
CREATE POLICY "Users see own AI conversations"
  ON public.ai_conversations FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- ---------------------------------------------------------------------------
-- 2. Engine substrate -- content editors only.
--
--    Prior: "intel read"     ON exercise_intelligence FOR SELECT USING (true)
--           "mie nodes read" ON movement_nodes        FOR SELECT USING (true)
--           "mie edges read" ON movement_edges        FOR SELECT USING (true)
--
--    The client keeps its access through movement_graph() / rank_exercises() /
--    score_exercise(), which are SECURITY DEFINER and therefore read these
--    tables as the owner regardless of the policy below.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "intel read" ON public.exercise_intelligence;
DROP POLICY IF EXISTS "intel read staff only" ON public.exercise_intelligence;
CREATE POLICY "intel read staff only"
  ON public.exercise_intelligence FOR SELECT TO authenticated
  USING (public.is_content_editor());

DROP POLICY IF EXISTS "mie nodes read" ON public.movement_nodes;
DROP POLICY IF EXISTS "mie nodes read staff only" ON public.movement_nodes;
CREATE POLICY "mie nodes read staff only"
  ON public.movement_nodes FOR SELECT TO authenticated
  USING (public.is_content_editor());

DROP POLICY IF EXISTS "mie edges read" ON public.movement_edges;
DROP POLICY IF EXISTS "mie edges read staff only" ON public.movement_edges;
CREATE POLICY "mie edges read staff only"
  ON public.movement_edges FOR SELECT TO authenticated
  USING (public.is_content_editor());

COMMENT ON TABLE public.movement_nodes IS
  'Movement graph -- deterministic engine substrate. Not client-readable '
  '(migration 117); the app reads it through movement_graph(), which is '
  'SECURITY DEFINER. Writes are service_role / mie_upsert_node() only.';
COMMENT ON TABLE public.exercise_intelligence IS
  'Certified exercise intelligence with confidence and provenance -- engine '
  'substrate, content-editor readable only (migration 117). Writes go through '
  'the content pipeline functions, never from a client.';

-- ---------------------------------------------------------------------------
-- 3. user_scores -- own row and the member's active coach.
--    Prior: "read user_scores" FOR SELECT USING (true)
--
--    Leaderboards keep working: leaderboard_global() and leaderboard_coach()
--    aggregate this table and are unaffected by the policy.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "read user_scores" ON public.user_scores;
DROP POLICY IF EXISTS "own or coached user_scores" ON public.user_scores;
CREATE POLICY "own or coached user_scores"
  ON public.user_scores FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.is_active_coach_of(user_id)
  );

-- ---------------------------------------------------------------------------
-- 4. Programming -- the owning coach, the assigned client, that client's coach.
--    Prior: "all read programs"          FOR SELECT USING (true)
--           "all read program workouts"  FOR SELECT USING (true)
--
--    The existing "coaches manage ..." FOR ALL policies are left exactly as they
--    are; these replace only the world-readable SELECT companions.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_read_program(p_program uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.workout_programs p
                  WHERE p.id = p_program AND p.coach_id = (SELECT auth.uid()))
      OR EXISTS (SELECT 1 FROM public.workout_program_assignments a
                  WHERE a.program_id = p_program
                    AND (a.client_id = (SELECT auth.uid())
                         OR a.coach_id = (SELECT auth.uid())
                         OR public.is_active_coach_of(a.client_id)))
      OR public.is_admin();
$$;

REVOKE ALL ON FUNCTION public.can_read_program(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_program(uuid) TO authenticated;

DROP POLICY IF EXISTS "all read programs" ON public.workout_programs;
DROP POLICY IF EXISTS "read own or assigned programs" ON public.workout_programs;
CREATE POLICY "read own or assigned programs"
  ON public.workout_programs FOR SELECT TO authenticated
  USING (
    coach_id = (SELECT auth.uid())
    OR public.can_read_program(id)
  );

DROP POLICY IF EXISTS "all read program workouts" ON public.program_workouts;
DROP POLICY IF EXISTS "read own or assigned program workouts" ON public.program_workouts;
CREATE POLICY "read own or assigned program workouts"
  ON public.program_workouts FOR SELECT TO authenticated
  USING (public.can_read_program(program_id));

COMMENT ON TABLE public.program_workouts IS
  'Materialized program days. Written by materialize_program_week() (the '
  'deterministic engine) and by the owning coach. Readable by the owning coach, '
  'the assigned client and that client''s active coach (migration 117) -- it was '
  'world-readable to every authenticated account before that.';

-- ---------------------------------------------------------------------------
-- 5. weekly_feedback -- engine input, so no client DELETE.
--    Prior: "weekly fb rw" FOR ALL TO authenticated
--             USING/CHECK (subject_id = auth.uid() OR caller owns the program)
--
--    Same predicate, split so DELETE is simply not granted. Erasure stays with
--    service_role, which is where provenance decisions belong.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "weekly fb rw" ON public.weekly_feedback;

DROP POLICY IF EXISTS "weekly fb read" ON public.weekly_feedback;
CREATE POLICY "weekly fb read"
  ON public.weekly_feedback FOR SELECT TO authenticated
  USING (
    subject_id = (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = weekly_feedback.program_id AND p.coach_id = (SELECT auth.uid()))
    OR public.is_active_coach_of(subject_id)
  );

DROP POLICY IF EXISTS "weekly fb insert" ON public.weekly_feedback;
CREATE POLICY "weekly fb insert"
  ON public.weekly_feedback FOR INSERT TO authenticated
  WITH CHECK (
    subject_id = (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = weekly_feedback.program_id AND p.coach_id = (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS "weekly fb update" ON public.weekly_feedback;
CREATE POLICY "weekly fb update"
  ON public.weekly_feedback FOR UPDATE TO authenticated
  USING (
    subject_id = (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = weekly_feedback.program_id AND p.coach_id = (SELECT auth.uid()))
  )
  WITH CHECK (
    subject_id = (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = weekly_feedback.program_id AND p.coach_id = (SELECT auth.uid()))
  );

REVOKE DELETE ON public.weekly_feedback FROM authenticated;

COMMENT ON TABLE public.weekly_feedback IS
  'Engine INPUT: evaluate_week() reads it and regenerate_program() acts on it. '
  'The subject and the owning coach may write it; nobody but service_role may '
  'delete it (migration 117), because deleting it rewrites the evidence a '
  'progression decision was made on.';

-- ---------------------------------------------------------------------------
-- 6. Moderation dashboards -- gate the engine-internal readers.
--
-- Migration 116 left these executable by any authenticated caller because they
-- are called from Flutter; they are called from the ADMIN screens, and they
-- project the engine's internal confidence, queue and analytics state. Same
-- rule as section 2, applied at the function boundary.
--
-- Guard shape is `auth.uid() IS NULL OR is_content_editor()`, so the internal
-- and service_role paths are untouched.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('intelligence_review_queue',    'intelligence_review_queue(integer)'),
      ('intelligence_stats',           'intelligence_stats()'),
      ('intelligence_low_confidence',  'intelligence_low_confidence(uuid,integer)'),
      ('decision_analytics',           'decision_analytics()'),
      ('movement_graph_stats',         'movement_graph_stats()'),
      ('exercise_content_stats',       'exercise_content_stats()'),
      ('attribute_review_state',       'attribute_review_state(uuid,integer)'),
      ('certification_summary',        'certification_summary()')
    ) AS t(nm, sig)
  LOOP
    IF to_regprocedure('public.' || r.sig) IS NOT NULL
       AND to_regprocedure('public.' || replace(r.sig, r.nm || '(', r.nm || '_engine(')) IS NULL THEN
      EXECUTE format('ALTER FUNCTION public.%s RENAME TO %I', r.sig, r.nm || '_engine');
      EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated',
                     replace(r.sig, r.nm || '(', r.nm || '_engine('));
      RAISE NOTICE '117: public.% renamed to %_engine', r.nm, r.nm;
    END IF;
  END LOOP;
END $$;

-- Wrappers reproduce each original signature and result type exactly; only the
-- guard is new. The *_engine originals keep the bodies, verified unchanged.
CREATE OR REPLACE FUNCTION public.intelligence_review_queue(p_limit integer DEFAULT 50)
RETURNS TABLE(exercise_id uuid, name text, status text, confidence integer, low_conf_count integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN QUERY SELECT * FROM public.intelligence_review_queue_engine(p_limit);
END;
$$;

CREATE OR REPLACE FUNCTION public.intelligence_stats()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN public.intelligence_stats_engine();
END;
$$;

CREATE OR REPLACE FUNCTION public.intelligence_low_confidence(p_id uuid, p_threshold integer DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN public.intelligence_low_confidence_engine(p_id, p_threshold);
END;
$$;

CREATE OR REPLACE FUNCTION public.decision_analytics()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN public.decision_analytics_engine();
END;
$$;

CREATE OR REPLACE FUNCTION public.movement_graph_stats()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN public.movement_graph_stats_engine();
END;
$$;

CREATE OR REPLACE FUNCTION public.attribute_review_state(p_exercise_id uuid, p_threshold integer DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN public.attribute_review_state_engine(p_exercise_id, p_threshold);
END;
$$;

CREATE OR REPLACE FUNCTION public.exercise_content_stats()
RETURNS TABLE(total bigint, draft bigint, ai_generated bigint, under_review bigint,
              needs_revision bigint, approved bigint, published bigint, archived bigint,
              human_reviewed bigint, ai_certified bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN QUERY SELECT * FROM public.exercise_content_stats_engine();
END;
$$;

CREATE OR REPLACE FUNCTION public.certification_summary()
RETURNS TABLE(total bigint, exercise_library bigint, workout_builder bigint,
              program_generator bigint, self_guided bigint, coach_guided bigint,
              ai_coach bigint, marketplace bigint, premium_content bigint,
              voice_coaching bigint, wearables bigint,
              avg_overall numeric, avg_projected numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.require_content_editor();
  RETURN QUERY SELECT * FROM public.certification_summary_engine();
END;
$$;

DO $$
DECLARE sig text;
BEGIN
  FOR sig IN
    SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname IN (
       'intelligence_review_queue', 'intelligence_stats', 'intelligence_low_confidence',
       'decision_analytics', 'movement_graph_stats', 'exercise_content_stats',
       'attribute_review_state', 'certification_summary')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.require_content_editor() IS
  'Raises 42501 unless the caller is an admin / content_manager. Internal and '
  'service_role callers (auth.uid() IS NULL) pass. Used to gate the moderation '
  'dashboard RPCs, which project deterministic-engine internals.';
