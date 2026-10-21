-- Simulated fix: the coach arm of each self-asserted policy also requires an active relationship.
alter policy "coach client habits" on public.client_habits using ((client_id = auth.uid()) or (coach_id = auth.uid() and public.is_active_coach_of(client_id)));
alter policy "coach manages assigned action items" on public.action_items using (coach_id = auth.uid() and public.is_active_coach_of(client_id));
drop policy "Coach and client can see calls" on public.coaching_calls;
alter policy "calls_participant_access" on public.coaching_calls using ((auth.uid() = client_id) or (auth.uid() = coach_id and public.is_active_coach_of(client_id)));
alter policy "Coach can insert video responses" on public.coach_video_responses with check (coach_id = auth.uid() and public.is_active_coach_of(client_id));
alter policy "coach client nutrition" on public.client_nutrition_plans using ((client_id = auth.uid()) or (coach_id = auth.uid() and public.is_active_coach_of(client_id)));
alter policy "coaches manage assignments" on public.workout_program_assignments using ((client_id = auth.uid()) or (coach_id = auth.uid() and public.is_active_coach_of(client_id)));
