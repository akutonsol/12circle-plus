-- ═══════════════════════════════════════════════════════════════════════════
-- 170 · COMMUNITY MODERATION — owner decisions CAP-1-1, CAP-1-2, CAP-1-3
--
-- CAP-1-1 = HIDE, PRESERVING THE MEMBER'S TEXT.
-- CAP-1-2 = a content_reports backing resource.
-- CAP-1-3 = Community/Create is NON-OPERATIONAL; staff do not post.
--
-- THE CONTENT COLUMN IS NEVER WRITTEN BY THIS MIGRATION OR ANY FUNCTION IN IT.
-- That is the whole point of CAP-1-1 and it is enforced by construction: the
-- moderation RPC lists the columns it sets, `content` is not among them, and no
-- policy added here permits an UPDATE of a post by anyone but its author. Staff can
-- take a post down; staff cannot put words in a member's mouth.
--
-- SCOPE IS POSTS AND COMMENTS, which is CAP-1's ruled scope. Reactions carry no
-- authored text and are out.
--
-- ── two vocabularies, and why only one is introduced ──────────────────────
-- `moderation_state` IS enumerated here — visible / hidden / removed — because the
-- owner's decision names the behaviour ("hide", with removal as the stronger form)
-- and the three states are the mechanism of that decision rather than a product
-- vocabulary layered on top of it.
--
-- A REPORT LIFECYCLE VOCABULARY IS **NOT** INTRODUCED. A report is open until it is
-- resolved: `resolved_at IS NULL` is the queue. Inventing `pending/triaged/actioned/
-- dismissed` would repeat exactly the mistake §141 and §142 refused — approval_status
-- and events.status both had no ruled vocabulary and nothing was built. Reason text
-- is FREE TEXT for the same reason: a fixed reason-code list is a product
-- vocabulary and must come from the owner.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · moderation state on the two content types ─────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['community_posts', 'post_comments'] LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS moderation_state text NOT NULL DEFAULT ''visible''', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS moderated_by uuid REFERENCES public.user_profiles(id)', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS moderated_at timestamptz', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS moderation_reason text', t);
    EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT IF EXISTS %I', t, t || '_moderation_state_check');
    EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (moderation_state = ANY (ARRAY[''visible''::text, ''hidden''::text, ''removed''::text]))', t, t || '_moderation_state_check');
  END LOOP;
END $$;

-- ── 2 · hidden content stops being readable — RESTRICTIVE, not a rewrite ──
-- The existing read policies ("all read posts", 001) are `USING (true)` and are NOT
-- touched. A permissive policy cannot narrow anything — they OR together — so this
-- is RESTRICTIVE, which ANDs with every permissive policy on the table. Nothing
-- previously readable by a given caller becomes readable; some of it stops being so.
--
-- THE AUTHOR KEEPS THEIR OWN. "Preserving the member's text" would be hollow if the
-- member could no longer see what they wrote, so `user_id = auth.uid()` is in the
-- predicate. The Admin layer sees everything, because it has to moderate it.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['community_posts', 'post_comments'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "moderated content is hidden" ON public.%I', t);
    EXECUTE format($q$CREATE POLICY "moderated content is hidden" ON public.%I
                      AS RESTRICTIVE FOR SELECT TO authenticated
                      USING (moderation_state = 'visible'
                             OR user_id = (SELECT auth.uid())
                             OR public.admin_can('Community', 'view'))$q$, t);
  END LOOP;
END $$;

-- ── 3 · reports — the queue's input (CAP-1-2) ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.content_reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id  uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  target_type  text NOT NULL,
  target_id    uuid NOT NULL,
  reason       text,                     -- FREE TEXT; a reason-code list is owner vocabulary
  created_at   timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz,              -- NULL = open. This IS the queue.
  resolved_by  uuid REFERENCES public.user_profiles(id),
  CONSTRAINT content_reports_target_type_check
    CHECK (target_type = ANY (ARRAY['post'::text, 'comment'::text])),
  CONSTRAINT content_reports_one_per_reporter UNIQUE (reporter_id, target_type, target_id)
);

COMMENT ON TABLE public.content_reports IS
  'V5 §151 · CAP-1-2. A report is OPEN while resolved_at IS NULL — that is the '
  'queue, and no lifecycle vocabulary is introduced (see §141/§142 on invented '
  'vocabularies). `reason` is free text: a fixed reason-code list is product '
  'vocabulary and must come from the owner. UNIQUE(reporter, target) so one member '
  'cannot inflate a queue by reporting the same item repeatedly.';

ALTER TABLE public.content_reports ENABLE ROW LEVEL SECURITY;

-- A member may file a report as themselves, and read only their own.
DROP POLICY IF EXISTS "members file their own reports" ON public.content_reports;
CREATE POLICY "members file their own reports" ON public.content_reports
  FOR INSERT TO authenticated WITH CHECK (reporter_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "members read their own reports" ON public.content_reports;
CREATE POLICY "members read their own reports" ON public.content_reports
  FOR SELECT TO authenticated USING (reporter_id = (SELECT auth.uid()));

-- The Admin layer reads the whole queue under the Community View grant.
DROP POLICY IF EXISTS "admin layer reads the report queue" ON public.content_reports;
CREATE POLICY "admin layer reads the report queue" ON public.content_reports
  FOR SELECT TO authenticated USING (public.admin_can('Community', 'view'));

REVOKE ALL ON TABLE public.content_reports FROM PUBLIC, anon, authenticated;
GRANT  SELECT, INSERT ON TABLE public.content_reports TO authenticated;
-- No UPDATE grant: resolution goes through the RPC, so it cannot be done untracked.

-- ── 4 · the moderation action (CAP-1-1) ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_moderate_content(
  p_target_type text,
  p_target_id   uuid,
  p_state       text,
  p_reason      text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_old text;
  v_subject uuid;
  v_ps  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Community', 'update') THEN
    RAISE EXCEPTION 'not authorized: Community/update is required' USING ERRCODE = '42501';
  END IF;
  IF p_target_type NOT IN ('post', 'comment') THEN
    RAISE EXCEPTION 'target_type must be post or comment' USING ERRCODE = '22023';
  END IF;
  IF p_state NOT IN ('visible', 'hidden', 'removed') THEN
    RAISE EXCEPTION 'moderation_state must be visible, hidden or removed' USING ERRCODE = '22023';
  END IF;
  p_reason := nullif(btrim(coalesce(p_reason, '')), '');
  -- Taking content down is explained; restoring it needs no justification.
  IF p_state <> 'visible' AND p_reason IS NULL THEN
    RAISE EXCEPTION 'hiding or removing content requires a reason' USING ERRCODE = '22023';
  END IF;

  IF p_target_type = 'post' THEN
    SELECT moderation_state, user_id INTO v_old, v_subject
      FROM public.community_posts WHERE id = p_target_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such post' USING ERRCODE = '22023'; END IF;
    -- `content` is NOT in this list. That is CAP-1-1.
    UPDATE public.community_posts
       SET moderation_state = p_state, moderated_by = v_uid,
           moderated_at = now(), moderation_reason = p_reason
     WHERE id = p_target_id;
  ELSE
    SELECT moderation_state, user_id INTO v_old, v_subject
      FROM public.post_comments WHERE id = p_target_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such comment' USING ERRCODE = '22023'; END IF;
    UPDATE public.post_comments
       SET moderation_state = p_state, moderated_by = v_uid,
           moderated_at = now(), moderation_reason = p_reason
     WHERE id = p_target_id;
  END IF;

  IF v_old IS NOT DISTINCT FROM p_state THEN
    RETURN;
  END IF;

  -- The SUBJECT is the member whose content was moderated, pseudonymised — so the
  -- record proves a moderation happened to someone without naming them. The state
  -- transition is carried as a delta because a moderation state is not personal
  -- data; the reason is NOT, because free text written by staff about a member is.
  v_ps := public.audit_mint_pseudonym(v_subject);
  PERFORM public.audit_record_event(
    p_action            => 'community_content.moderate',
    p_category          => 'admin_action',
    p_outcome           => 'success',
    p_subject_pseudonym => v_ps,
    p_delta             => jsonb_build_object(
                             'before', jsonb_build_object('moderation_state', v_old),
                             'after',  jsonb_build_object('moderation_state', p_state)),
    p_changed_columns   => ARRAY['moderation_state']);

  RAISE LOG 'admin_moderate_content: % set % % -> %', v_uid, p_target_type, p_target_id, p_state;
END;
$$;

ALTER FUNCTION public.admin_moderate_content(text, uuid, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_moderate_content(text, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_moderate_content(text, uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_moderate_content(text, uuid, text, text) IS
  'V5 §151 · CAP-1-1. Sets moderation_state and NEVER touches `content` — staff can '
  'take a post down, not rewrite it. Gated on admin_can(''Community'',''update''). '
  'Hiding or removing requires a reason. Audited as admin_action against the '
  'PSEUDONYMISED author, carrying the state transition but not the reason text.';

-- ── 5 · resolving a report ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_resolve_report(p_report_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_uid uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Community', 'update') THEN
    RAISE EXCEPTION 'not authorized: Community/update is required' USING ERRCODE = '42501';
  END IF;
  UPDATE public.content_reports
     SET resolved_at = now(), resolved_by = v_uid
   WHERE id = p_report_id AND resolved_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such open report' USING ERRCODE = '22023';
  END IF;
END;
$$;

ALTER FUNCTION public.admin_resolve_report(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_resolve_report(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_report(uuid) TO authenticated;
