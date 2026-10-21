-- Migration 104: record whether a logged set was actually completed
--
-- Since migration 051 a `workout_set_logs` row is written whenever the client
-- edits a set's weight/reps/RPE/notes — not only when the set is confirmed. The
-- app had no way to tell the two apart on resume, so every row came back marked
-- completed: a set the client had merely typed into showed a checkmark and
-- counted toward workout progress, and (once completed sets became immutable)
-- would have been locked without ever having been confirmed.
--
-- Completion is now stored rather than inferred, so a resumed workout shows
-- exactly the sets the client confirmed.
--
-- Existing rows default to true: that is precisely how the app has been reading
-- them, and the real completion state of a historical row is unrecoverable.
-- Defaulting the other way would silently un-complete recorded history.

alter table workout_set_logs
  add column if not exists completed boolean not null default true;

comment on column workout_set_logs.completed is
  'True once the client confirmed the set. Confirmed sets are immutable in the '
  'app: weight/reps/RPE change only through the explicit "Edit Completed Set" '
  'correction flow.';
