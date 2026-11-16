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
--     * upload / overwrite: an admin; the owning coach of a PRIVATE exercise
--       (custom_exercises "coaches manage own exercises"); and, for a PLATFORM
--       exercise (coach_id null), a coach or admin -- update_exercise_media's
--       existing rule (072);
--     * delete: an admin, or the owning coach of a private exercise. Platform
--       media is shared, so no single coach deletes it (the app never deletes
--       exercise media at all);
--     * public read is unchanged.
--   coach-media (paths are <kind>/<uploader id>/..., three call sites):
--     * upload / overwrite only inside your OWN folder, and only as a coach or
--       admin (adds the missing UPDATE policy, so upsert of your own file works);
--     * delete: unchanged -- "coach media manage own" (owner = auth.uid());
--     * read through the API: coach-videos/<coach>/<client>/... only by that coach
--       or that client; other paths unchanged. Nothing plays the videos today
--       (OD-57), so nothing that works is taken away.
--   update_exercise_media (072): keeps its coach/admin rule and search_path pin;
--     on a PRIVATE exercise it now also requires the owning coach or an admin, as
--     custom_exercises' own policy does (it was SECURITY DEFINER and bypassed it).
--
-- NOT CHANGED, AND WHY (owner decisions, recorded in the ledger):
--   * Both buckets stay PUBLIC: an object URL still serves without a session.
--     Making coach-media private (SEC-VIDEO-1's stated next step) breaks the
--     public transformation images, which still use getPublicUrl -- a product/
--     infra decision.
--   * On a PLATFORM exercise any coach may still replace another coach's media
--     (update_exercise_media's rule). Whether platform media has an owner, and
--     whether content_manager may edit it, is owner decision 15.
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
  SELECT CASE
    WHEN (storage.foldername(p_name))[1] IS DISTINCT FROM 'exercises' THEN false
    ELSE COALESCE((
      SELECT public.is_admin()
          OR (e.coach_id IS NULL AND EXISTS (
                SELECT 1 FROM public.user_profiles u
                 WHERE u.id = (SELECT auth.uid()) AND u.role IN ('coach', 'admin')))
          OR (e.coach_id IS NOT NULL AND e.coach_id = (SELECT auth.uid()))
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
  SELECT CASE
    WHEN (storage.foldername(p_name))[1] IS DISTINCT FROM 'exercises' THEN false
    ELSE COALESCE((
      SELECT public.is_admin()
          OR (e.coach_id IS NOT NULL AND e.coach_id = (SELECT auth.uid()))
        FROM public.custom_exercises e
       WHERE e.id::text = (storage.foldername(p_name))[2]), false)
  END;
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

DROP POLICY IF EXISTS "exercise-media delete by owner or admin" ON storage.objects;
CREATE POLICY "exercise-media delete by owner or admin" ON storage.objects
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

-- ── update_exercise_media: a private exercise's media is its coach's ─────────
CREATE OR REPLACE FUNCTION public.update_exercise_media(p_id uuid, p_image_url text, p_video_variants jsonb)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
declare
  v_role  text;
  v_owner uuid;
begin
  select role into v_role from user_profiles where id = auth.uid();
  if v_role is null or v_role not in ('coach', 'admin') then
    raise exception 'not authorized to add media';
  end if;
  select coach_id into v_owner from custom_exercises where id = p_id;
  -- 199: a PRIVATE exercise (coach_id set) is edited only by its coach or an
  -- admin, as custom_exercises' own policy says. Platform exercises keep 072's rule.
  if v_owner is not null and v_owner <> auth.uid() and v_role <> 'admin' then
    raise exception 'not authorized to add media';
  end if;
  update custom_exercises
     set image_url = coalesce(p_image_url, image_url),
         video_variants = coalesce(p_video_variants, video_variants)
   where id = p_id;
  return found;
end;
$function$;

COMMIT;
