-- Migration 190. A personal record is announced only for a set the client
-- CONFIRMED, measured only against sets the client confirmed.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["190"]; environments.qa.applied_through is "181".
--
-- THE DEFECT (live definition read from QA, 2026-11-14). The app writes a
-- workout_set_logs row for a set the client has merely FILLED IN, with
-- completed = false, and flips it to true when they confirm it (migration 104).
-- detect_pr_on_set_log (AFTER INSERT and AFTER UPDATE) ignores `completed` twice:
--   * it fires for an unconfirmed row, so typing a heavier weight into a set the
--     client never performs sends "New Personal Record! 🎉" to the client and
--     "Client PR 🎉" to their coach;
--   * the prior best it compares against includes unconfirmed rows, so a weight
--     typed and abandoned once raises the bar every real set is measured against.
-- The app's own records already count confirmed sets only (PR #132,
-- "records count confirmed sets only"); the database disagreed with it.
--
-- THE FIX. Two clauses. `completed IS NOT FALSE` -- rows written before migration
-- 104 have no flag and have always been read as completed, which is kept. The rest
-- of the body is the live definition, unchanged.
--
-- FUNCTION REPLACEMENT RULE. Same signature, SECURITY DEFINER, pinned
-- search_path restated; EXECUTE stays revoked from PUBLIC (a trigger function).

BEGIN;

CREATE OR REPLACE FUNCTION public.detect_pr_on_set_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
declare
  v_prior numeric; v_coach uuid; v_name text; v_recent int; v_supports boolean;
begin
  if NEW.weight_kg is null or NEW.weight_kg <= 0 then return NEW; end if;
  -- Migration 190: an unconfirmed set is not a performance.
  if NEW.completed is false then return NEW; end if;
  -- Respect the exercise's PR-tracking flag (only an exact library match with
  -- the flag false suppresses PR detection).
  select supports_pr_tracking into v_supports from custom_exercises
   where lower(name) = lower(NEW.exercise_name) and visibility = 'global'
     and submission_status = 'approved' limit 1;
  if v_supports is false then return NEW; end if;
  select max(weight_kg) into v_prior from workout_set_logs
   where user_id = NEW.user_id and exercise_name = NEW.exercise_name and id <> NEW.id
     and completed is not false;               -- migration 190: confirmed sets only
  if v_prior is null or v_prior <= 0 or NEW.weight_kg <= v_prior then return NEW; end if;
  select count(*) into v_recent from notifications
   where recipient_id = NEW.user_id and type = 'pr_achieved'
     and data->>'exercise' = NEW.exercise_name and created_at > now() - interval '2 hours';
  if v_recent > 0 then return NEW; end if;
  select nullif(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,'')), '') into v_name
    from user_profiles where id = NEW.user_id;
  insert into notifications (recipient_id, type, title, body, data, read)
  values (NEW.user_id, 'pr_achieved', 'New Personal Record! 🎉',
          'You hit a new PR on ' || NEW.exercise_name || ': ' ||
          trim(to_char(NEW.weight_kg, 'FM999990.0')) || ' kg.',
          jsonb_build_object('exercise', NEW.exercise_name, 'weight_kg', NEW.weight_kg), false);
  select coach_id into v_coach from coach_client_relationships
   where client_id = NEW.user_id and status = 'active'
   order by activated_at desc nulls last limit 1;
  if v_coach is not null then
    insert into notifications (recipient_id, type, title, body, data, read)
    values (v_coach, 'pr_achieved', 'Client PR 🎉',
            coalesce(v_name, 'Your client') || ' hit a new PR on ' || NEW.exercise_name || ': ' ||
            trim(to_char(NEW.weight_kg, 'FM999990.0')) || ' kg.',
            jsonb_build_object('client_id', NEW.user_id, 'exercise', NEW.exercise_name,
                               'weight_kg', NEW.weight_kg), false);
  end if;
  return NEW;
end;
$$;

REVOKE ALL ON FUNCTION public.detect_pr_on_set_log() FROM PUBLIC, anon, authenticated;

COMMIT;
