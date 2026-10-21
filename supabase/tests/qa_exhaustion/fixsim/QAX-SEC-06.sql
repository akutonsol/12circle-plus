-- Simulated fix: the definer view applies the same visibility rule as custom_exercises RLS.
create or replace view public.exercises as select * from public.custom_exercises
 where (visibility = 'global' and submission_status = 'approved') or coach_id = auth.uid() or public.is_admin();
