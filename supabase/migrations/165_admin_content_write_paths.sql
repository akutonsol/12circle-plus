-- ═══════════════════════════════════════════════════════════════════════════
-- 165 · EVENTS AND TRAINING CONTENT WRITE PATHS — owner decisions B-22b and
--        B-22c, 2026-10-06
--
-- B-22 was taken as THREE separate decisions with three different hazards, not one
-- "content write" generalisation of the Users whitelist.
--
--  · Community (B-22a) -> DEFERRED, and NOT built. Its write grants resolve into
--    MODERATION -- community_posts is "users manage own posts", so a content_editor
--    Update means editing another member's words -- and the reports/moderation
--    queue the approved design names DOES NOT EXIST (§127; CAP-1, parked as B-10).
--    Deliberately NOT added to the non-operational register: unlike B-20's six,
--    these WILL become operational once CAP-1 is decided, and recording them as
--    "authorized and not offered" would assert something false about the future.
--  · Events   (B-22b) -> descriptive fields only (below)
--  · Training (B-22c) -> template authoring only (below)
--
-- WHY FUNCTIONS AND NOT POLICIES, AGAIN. A policy constrains WHICH ROWS a caller
-- may write, never WHICH COLUMNS, and column privileges are per-role while
-- `authenticated` is one role shared by every member. The contract is the function
-- body, enforced server-side; no UI-only authorization.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · EVENTS — owner decision B-22b: DESCRIPTIVE FIELDS ONLY ─────────────
-- FOUR COLUMN GROUPS ARE EXCLUDED, each for a stated reason:
--   · price, is_free        MONETIZATION. COWORK_ENGINEERING_GOVERNANCE §8 bars an
--                           agent from inventing pricing policy, and the owner did
--                           not extend the contract to cover it.
--   · current_registered    a registration counter with NO trigger maintaining it.
--                           Writing it would desync attendance from the actual
--                           event_registrations rows, which K-04 exists to protect.
--   · status                NO CHECK and NO ruled vocabulary — only 'upcoming'
--                           exists live. The same condition that blocks
--                           Incidents/Approve (§141), and inventing values here
--                           would be the same mistake.
--   · vendor_id             ownership. Writing it reassigns the event.
CREATE OR REPLACE FUNCTION public.admin_create_event(
  p_title           text,
  p_event_date      timestamptz,
  p_description     text        DEFAULT NULL,
  p_location        text        DEFAULT NULL,
  p_end_date        timestamptz DEFAULT NULL,
  p_cover_image_url text        DEFAULT NULL,
  p_host_name       text        DEFAULT NULL,
  p_max_capacity    int         DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_id uuid; v_ps uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Events', 'create') THEN
    RAISE EXCEPTION 'not authorized: Events/create is required' USING ERRCODE = '42501';
  END IF;
  p_title := nullif(btrim(coalesce(p_title, '')), '');
  IF p_title IS NULL THEN RAISE EXCEPTION 'an event needs a title' USING ERRCODE = '22023'; END IF;
  IF p_event_date IS NULL THEN RAISE EXCEPTION 'an event needs a date' USING ERRCODE = '22023'; END IF;
  IF p_max_capacity IS NOT NULL AND p_max_capacity < 0 THEN
    RAISE EXCEPTION 'max_capacity cannot be negative' USING ERRCODE = '22023';
  END IF;

  -- price, is_free, status, current_registered and vendor_id are NOT set here;
  -- they take their column defaults, so a staff-created event is free, upcoming,
  -- unowned and empty until some other authorized path changes that.
  INSERT INTO public.events (title, event_date, description, location, end_date,
                             cover_image_url, host_name, max_capacity)
  VALUES (p_title, p_event_date, p_description, p_location, p_end_date,
          p_cover_image_url, p_host_name, p_max_capacity)
  RETURNING id INTO v_id;

  v_ps := public.audit_mint_pseudonym((SELECT auth.uid()));
  PERFORM public.audit_record_event(
    p_action => 'events.create', p_category => 'admin_action', p_outcome => 'success',
    p_subject_pseudonym => v_ps, p_delta => NULL, p_changed_columns => ARRAY['title']);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_event(
  p_event_id        uuid,
  p_title           text        DEFAULT NULL,
  p_description     text        DEFAULT NULL,
  p_location        text        DEFAULT NULL,
  p_event_date      timestamptz DEFAULT NULL,
  p_end_date        timestamptz DEFAULT NULL,
  p_cover_image_url text        DEFAULT NULL,
  p_host_name       text        DEFAULT NULL,
  p_max_capacity    int         DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_changed text[] := ARRAY[]::text[]; v_ps uuid; v_old record;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Events', 'update') THEN
    RAISE EXCEPTION 'not authorized: Events/update is required' USING ERRCODE = '42501';
  END IF;
  p_title := nullif(btrim(coalesce(p_title, '')), '');
  IF p_max_capacity IS NOT NULL AND p_max_capacity < 0 THEN
    RAISE EXCEPTION 'max_capacity cannot be negative' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'no such event' USING ERRCODE = '22023'; END IF;

  -- COALESCE throughout: a NULL argument leaves that column alone, so this can
  -- never blank a field it was not asked to change.
  UPDATE public.events
     SET title           = coalesce(p_title,           title),
         description     = coalesce(p_description,     description),
         location        = coalesce(p_location,        location),
         event_date      = coalesce(p_event_date,      event_date),
         end_date        = coalesce(p_end_date,        end_date),
         cover_image_url = coalesce(p_cover_image_url, cover_image_url),
         host_name       = coalesce(p_host_name,       host_name),
         max_capacity    = coalesce(p_max_capacity,    max_capacity)
   WHERE id = p_event_id;

  IF p_title           IS NOT NULL AND p_title           IS DISTINCT FROM v_old.title           THEN v_changed := array_append(v_changed, 'title'); END IF;
  IF p_description     IS NOT NULL AND p_description     IS DISTINCT FROM v_old.description     THEN v_changed := array_append(v_changed, 'description'); END IF;
  IF p_location        IS NOT NULL AND p_location        IS DISTINCT FROM v_old.location        THEN v_changed := array_append(v_changed, 'location'); END IF;
  IF p_event_date      IS NOT NULL AND p_event_date      IS DISTINCT FROM v_old.event_date      THEN v_changed := array_append(v_changed, 'event_date'); END IF;
  IF p_end_date        IS NOT NULL AND p_end_date        IS DISTINCT FROM v_old.end_date        THEN v_changed := array_append(v_changed, 'end_date'); END IF;
  IF p_cover_image_url IS NOT NULL AND p_cover_image_url IS DISTINCT FROM v_old.cover_image_url THEN v_changed := array_append(v_changed, 'cover_image_url'); END IF;
  IF p_host_name       IS NOT NULL AND p_host_name       IS DISTINCT FROM v_old.host_name       THEN v_changed := array_append(v_changed, 'host_name'); END IF;
  IF p_max_capacity    IS NOT NULL AND p_max_capacity    IS DISTINCT FROM v_old.max_capacity    THEN v_changed := array_append(v_changed, 'max_capacity'); END IF;

  IF array_length(v_changed, 1) IS NULL THEN RETURN; END IF;

  v_ps := public.audit_mint_pseudonym((SELECT auth.uid()));
  PERFORM public.audit_record_event(
    p_action => 'events.update', p_category => 'admin_action', p_outcome => 'success',
    p_subject_pseudonym => v_ps, p_delta => NULL, p_changed_columns => v_changed);
END;
$$;

-- ── 2 · TRAINING — owner decision B-22c: TEMPLATE AUTHORING ONLY ───────────
-- EXCLUDED, each because another system owns it:
--   · coach_id          PRIVILEGE-BEARING. "coaches manage programs" keys on it, so
--                       writing it reassigns ownership — the same shape as
--                       actor_identity in §141.
--   · program_version   maintained by snapshot_program_version() and the engine
--                       RPCs (093:123, 116:299).
--   · plan, strategy, engine_generated   engine output, not hand-authored content.
--
-- B-3 IS NOT IMPLICATED, and this is worth stating because the area is called
-- Training: workout_programs holds program TEMPLATES, not member training records.
-- Member history lives in workout_sessions and workout_logs, which stay
-- aggregate-only and are asserted so on every run.
--
-- A CONSEQUENCE OF THE CHOSEN CONTRACT, recorded rather than hidden: `is_template`
-- is writable, and the owner chose the unrestricted option over the one that would
-- have refused any program with is_template = false. So a content editor can edit
-- the authoring fields of a coach-assigned program, and can flip a program between
-- template and assigned. That is the contract as decided; narrowing it later is an
-- owner decision, not a defect.
CREATE OR REPLACE FUNCTION public.admin_create_program_template(
  p_name           text,
  p_description    text DEFAULT NULL,
  p_goal           text DEFAULT NULL,
  p_difficulty     text DEFAULT NULL,
  p_duration_weeks int  DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_id uuid; v_ps uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Training', 'create') THEN
    RAISE EXCEPTION 'not authorized: Training/create is required' USING ERRCODE = '42501';
  END IF;
  p_name := nullif(btrim(coalesce(p_name, '')), '');
  IF p_name IS NULL THEN RAISE EXCEPTION 'a program needs a name' USING ERRCODE = '22023'; END IF;
  IF p_duration_weeks IS NOT NULL AND p_duration_weeks <= 0 THEN
    RAISE EXCEPTION 'duration_weeks must be positive' USING ERRCODE = '22023';
  END IF;

  -- coach_id is left NULL: a staff-authored template belongs to no coach, and this
  -- function must not assign ownership.
  INSERT INTO public.workout_programs (name, description, goal, difficulty,
                                       duration_weeks, is_template)
  VALUES (p_name, p_description, p_goal,
          coalesce(p_difficulty, 'intermediate'),
          coalesce(p_duration_weeks, 12), true)
  RETURNING id INTO v_id;

  v_ps := public.audit_mint_pseudonym((SELECT auth.uid()));
  PERFORM public.audit_record_event(
    p_action => 'workout_programs.create', p_category => 'admin_action', p_outcome => 'success',
    p_subject_pseudonym => v_ps, p_delta => NULL, p_changed_columns => ARRAY['name']);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_program_template(
  p_program_id     uuid,
  p_name           text    DEFAULT NULL,
  p_description    text    DEFAULT NULL,
  p_goal           text    DEFAULT NULL,
  p_difficulty     text    DEFAULT NULL,
  p_duration_weeks int     DEFAULT NULL,
  p_is_template    boolean DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_changed text[] := ARRAY[]::text[]; v_ps uuid; v_old record;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Training', 'update') THEN
    RAISE EXCEPTION 'not authorized: Training/update is required' USING ERRCODE = '42501';
  END IF;
  p_name := nullif(btrim(coalesce(p_name, '')), '');
  IF p_duration_weeks IS NOT NULL AND p_duration_weeks <= 0 THEN
    RAISE EXCEPTION 'duration_weeks must be positive' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM public.workout_programs WHERE id = p_program_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'no such program' USING ERRCODE = '22023'; END IF;

  UPDATE public.workout_programs
     SET name           = coalesce(p_name,           name),
         description    = coalesce(p_description,    description),
         goal           = coalesce(p_goal,           goal),
         difficulty     = coalesce(p_difficulty,     difficulty),
         duration_weeks = coalesce(p_duration_weeks, duration_weeks),
         is_template    = coalesce(p_is_template,    is_template)
   WHERE id = p_program_id;

  IF p_name           IS NOT NULL AND p_name           IS DISTINCT FROM v_old.name           THEN v_changed := array_append(v_changed, 'name'); END IF;
  IF p_description    IS NOT NULL AND p_description    IS DISTINCT FROM v_old.description    THEN v_changed := array_append(v_changed, 'description'); END IF;
  IF p_goal           IS NOT NULL AND p_goal           IS DISTINCT FROM v_old.goal           THEN v_changed := array_append(v_changed, 'goal'); END IF;
  IF p_difficulty     IS NOT NULL AND p_difficulty     IS DISTINCT FROM v_old.difficulty     THEN v_changed := array_append(v_changed, 'difficulty'); END IF;
  IF p_duration_weeks IS NOT NULL AND p_duration_weeks IS DISTINCT FROM v_old.duration_weeks THEN v_changed := array_append(v_changed, 'duration_weeks'); END IF;
  IF p_is_template    IS NOT NULL AND p_is_template    IS DISTINCT FROM v_old.is_template    THEN v_changed := array_append(v_changed, 'is_template'); END IF;

  IF array_length(v_changed, 1) IS NULL THEN RETURN; END IF;

  v_ps := public.audit_mint_pseudonym((SELECT auth.uid()));
  PERFORM public.audit_record_event(
    p_action => 'workout_programs.update', p_category => 'admin_action', p_outcome => 'success',
    p_subject_pseudonym => v_ps, p_delta => NULL, p_changed_columns => v_changed);
END;
$$;

-- ── 3 · grants ─────────────────────────────────────────────────────────────
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.admin_create_event(text,timestamptz,text,text,timestamptz,text,text,int)',
    'public.admin_update_event(uuid,text,text,text,timestamptz,timestamptz,text,text,int)',
    'public.admin_create_program_template(text,text,text,text,int)',
    'public.admin_update_program_template(uuid,text,text,text,text,int,boolean)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', f);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END $$;
