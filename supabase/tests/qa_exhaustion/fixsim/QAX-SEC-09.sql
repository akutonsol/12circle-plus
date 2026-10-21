-- Simulated fix: event hosts lose the full-profile arm; they use public_profiles for registrant names.
alter policy "own profile or active coach reads profile" on public.user_profiles
  using ((id = auth.uid()) or public.is_active_coach_of(id) or public.is_team_lead_of(id));
