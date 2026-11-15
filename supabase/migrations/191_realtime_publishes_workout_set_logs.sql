-- Migration 191. workout_set_logs joins the supabase_realtime publication.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["191"]; environments.qa.applied_through is "181".
--
-- THE DEFECT (live publication read from QA, 2026-11-14). The app subscribes to
-- workout_set_logs changes -- programSessionStatusProvider
-- (lib/features/workout/domain/workout_provider.dart) watches
-- tableTickerProvider('workout_set_logs') beside 'workout_sessions' -- but the
-- table is not in supabase_realtime, so that ticker never fires: a set saved on
-- one device, or by the session restore path, does not refresh the program's
-- per-session status until something else invalidates it. Every other table the
-- app watches through tableTickerProvider is already published.
--
-- THE FIX. Add the table, idempotently. Realtime postgres_changes are filtered
-- through the table's RLS for each subscriber, so this widens no read: a client
-- receives only the set-log rows it can already SELECT (its own; its coach's
-- through the existing coach read policy).

BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (SELECT 1 FROM pg_publication_tables
                      WHERE pubname = 'supabase_realtime'
                        AND schemaname = 'public' AND tablename = 'workout_set_logs') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.workout_set_logs;
  END IF;
END $$;

COMMIT;
