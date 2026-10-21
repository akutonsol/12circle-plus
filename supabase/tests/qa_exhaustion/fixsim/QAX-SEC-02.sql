-- Simulated fix: only an ACTIVE coach of the folder owner may read progress photos.
drop policy "coach reads client progress photos" on storage.objects;
create policy "coach reads client progress photos" on storage.objects for select to authenticated
  using (bucket_id = 'progress-photos' and exists (select 1 from public.coach_client_relationships r
         where r.coach_id = auth.uid() and r.status = 'active' and r.client_id::text = (storage.foldername(name))[1]));
