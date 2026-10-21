-- Simulated fix: coach-media uploads only into the uploader's own folder.
alter policy "coach media insert" on storage.objects
  with check (bucket_id = 'coach-media' and (storage.foldername(name))[1] = auth.uid()::text);
