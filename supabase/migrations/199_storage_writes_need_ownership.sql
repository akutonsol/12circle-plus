-- Migration 199. Storage writes need ownership: exercise-media and coach-media.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["199"]. Independent of 182-186 and 193-198.
--
-- THE DEFECTS (supabase/tests/local/storage_199_replay.sql, 12 FAIL on 000-198)
--   exercise-media (061, PUBLIC bucket): "auth write", "auth update" and
--   "auth delete" check only bucket_id. Any signed-in user -- a client included --
--   could upload anywhere in the bucket, overwrite any exercise's image or video,
--   or delete it, and every user is served the result. 061's own comment says the
--   writers were meant to be "coaches/admins".
--   coach-media (036, PUBLIC bucket): "coach media insert" checks only bucket_id,
--   so a client could upload, and anyone could write into another coach's folder;
--   "coach media read" let ANY signed-in user list and sign every object --
--   including coach-videos/<coach>/<client>/..., a coach's video to a named client.
--
-- THE RULES, each mirroring an authority that already exists -- none is new:
--   exercise-media (paths are exercises/<exercise id>/<file>, CustomExerciseService):
--     * the path must name an EXISTING exercise (the app uploads after the row);
--     * PLATFORM exercise (coach_id null) -- shared by every coach: upload,
--       overwrite and delete only by a CONTENT EDITOR, public.is_content_editor()
--       = admin or content_manager (083; the role that already runs the content
--       pipeline -- review, intelligence, warm-up seed). Other coaches read and
--       use platform exercises but cannot replace or remove shared media
--       (owner decision 15, direction 2026-11-16);
--     * PRIVATE exercise (coach_id set): upload, overwrite and delete only by its
--       coach or an admin (custom_exercises "coaches manage own exercises" +
--       "admin moderate exercises");
--     * public read is unchanged.
--   coach-media (paths are <kind>/<uploader id>/..., three call sites):
--     * upload / overwrite only inside your OWN folder, and only as a coach or
--       admin (adds the missing UPDATE policy, so upsert of your own file works);
--     * delete: unchanged -- "coach media manage own" (owner = auth.uid());
--     * read through the API: coach-videos/<coach>/<client>/... only by that coach
--       or that client; other paths unchanged. Nothing plays the videos today
--       (OD-57), so nothing that works is taken away.
--   update_exercise_media (072): the same rule as the bucket -- platform exercise:
--     content editors only; private exercise: its coach or an admin. 072 let any
--     coach or admin set media on ANY exercise (and refused content_manager, so
--     the content role had no working media path at all).
--
-- NOT CHANGED, AND WHY (owner decisions, recorded in the ledger):
--   * Both buckets stay PUBLIC: an object URL still serves without a session.
--     Making coach-media private (SEC-VIDEO-1's stated next step) breaks the
--     public transformation images, which still use getPublicUrl -- a product/
--     infra decision.
--   * Decision 15b (direction 2026-11-16): coach-media stays PUBLIC until the
--     public transformation images have their own media location; see the ledger.
--
-- Reversible: drop the policies below and recreate 061's and 036's; restore 072's
-- function body.

BEGIN;

-- ── helpers ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_write_exercise_media(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  -- Upload, overwrite AND delete use one rule (decision 15): platform media is
  -- the content editors'; private media is its coach's (and an admin's).
  SELECT CASE
    WHEN (storage.foldername(p_name))[1] IS DISTINCT FROM 'exercises' THEN false
    ELSE COALESCE((
      SELECT CASE
               WHEN e.coach_id IS NULL THEN public.is_content_editor()
               ELSE e.coach_id = (SELECT auth.uid()) OR public.is_admin()
             END
        FROM public.custom_exercises e
       WHERE e.id::text = (storage.foldername(p_name))[2]), false)
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_delete_exercise_media(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.can_write_exercise_media(p_name);
$$;

REVOKE ALL ON FUNCTION public.can_write_exercise_media(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_delete_exercise_media(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_write_exercise_media(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_delete_exercise_media(text) TO authenticated;

-- ── exercise-media ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "exercise-media auth write" ON storage.objects;
DROP POLICY IF EXISTS "exercise-media auth update" ON storage.objects;
DROP POLICY IF EXISTS "exercise-media auth delete" ON storage.objects;

DROP POLICY IF EXISTS "exercise-media write by exercise editor" ON storage.objects;
CREATE POLICY "exercise-media write by exercise editor" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'exercise-media' AND public.can_write_exercise_media(name));

DROP POLICY IF EXISTS "exercise-media overwrite by exercise editor" ON storage.objects;
CREATE POLICY "exercise-media overwrite by exercise editor" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'exercise-media' AND public.can_write_exercise_media(name))
  WITH CHECK (bucket_id = 'exercise-media' AND public.can_write_exercise_media(name));

DROP POLICY IF EXISTS "exercise-media delete by exercise editor" ON storage.objects;
CREATE POLICY "exercise-media delete by exercise editor" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'exercise-media' AND public.can_delete_exercise_media(name));

-- ── coach-media ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "coach media insert" ON storage.objects;
DROP POLICY IF EXISTS "coach media read" ON storage.objects;

DROP POLICY IF EXISTS "coach media upload to own folder" ON storage.objects;
CREATE POLICY "coach media upload to own folder" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'coach-media'
    AND (storage.foldername(name))[2] = (SELECT auth.uid())::text
    AND EXISTS (SELECT 1 FROM public.user_profiles u
                 WHERE u.id = (SELECT auth.uid()) AND u.role IN ('coach', 'admin'))
  );

DROP POLICY IF EXISTS "coach media overwrite own folder" ON storage.objects;
CREATE POLICY "coach media overwrite own folder" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'coach-media'
    AND (storage.foldername(name))[2] = (SELECT auth.uid())::text
    AND EXISTS (SELECT 1 FROM public.user_profiles u
                 WHERE u.id = (SELECT auth.uid()) AND u.role IN ('coach', 'admin'))
  )
  WITH CHECK (
    bucket_id = 'coach-media'
    AND (storage.foldername(name))[2] = (SELECT auth.uid())::text
    AND EXISTS (SELECT 1 FROM public.user_profiles u
                 WHERE u.id = (SELECT auth.uid()) AND u.role IN ('coach', 'admin'))
  );

DROP POLICY IF EXISTS "coach media read, videos by coach and client" ON storage.objects;
CREATE POLICY "coach media read, videos by coach and client" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'coach-media'
    AND (
      (storage.foldername(name))[1] IS DISTINCT FROM 'coach-videos'
      OR (storage.foldername(name))[2] = (SELECT auth.uid())::text
      OR (storage.foldername(name))[3] = (SELECT auth.uid())::text
    )
  );

-- ── update_exercise_media: the same rule as the bucket ────────────────────────
CREATE OR REPLACE FUNCTION public.update_exercise_media(p_id uuid, p_image_url text, p_video_variants jsonb)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
declare
  v_found boolean;
  v_owner uuid;
begin
  select true, coach_id into v_found, v_owner from custom_exercises where id = p_id;
  if v_found is null then
    return false;
  end if;
  -- 199 (decision 15): the bucket's rule. Platform exercise: content editors
  -- (admin, content_manager). Private exercise: its coach or an admin.
  if v_owner is null then
    if not public.is_content_editor() then
      raise exception 'not authorized to add media' using errcode = '42501';
    end if;
  elsif v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'not authorized to add media' using errcode = '42501';
  end if;
  update custom_exercises
     set image_url = coalesce(p_image_url, image_url),
         video_variants = coalesce(p_video_variants, video_variants)
   where id = p_id;
  return found;
end;
$function$;

COMMIT;
