-- Simulated fix: exercise-media update/delete limited to the uploading owner.
alter policy "exercise-media auth delete" on storage.objects using (bucket_id = 'exercise-media' and owner = auth.uid());
alter policy "exercise-media auth update" on storage.objects using (bucket_id = 'exercise-media' and owner = auth.uid());
