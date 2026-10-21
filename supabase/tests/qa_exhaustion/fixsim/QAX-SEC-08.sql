-- Simulated fix: a team membership row can only be created by the member (consent), never by the lead.
alter policy "Head coach manages team" on public.coach_team_members using (coach_id = auth.uid()) with check (false);
create policy "qax member joins team" on public.coach_team_members for insert to authenticated with check (member_id = auth.uid());
