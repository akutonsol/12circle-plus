-- Migration 199 regression: storage writes need ownership. LOCAL REPLAY only
-- (loopback scratch DB; the shim models storage.objects with RLS, which is what
-- Supabase Storage enforces). One transaction, always ROLLED BACK. Each write is
-- issued as `authenticated` with JWT claims. Every refusal has a positive control.
-- Output: `PASS|id|detail` or `FAIL|id|detail` per assertion.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated;
grant usage on schema storage to authenticated;
grant select, insert, update, delete on storage.objects to authenticated;

create function pg_temp.run_as(u uuid, stmt text) returns text language plpgsql as $$
declare r text; n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true);
  set local role authenticated;
  begin execute stmt; get diagnostics n = row_count; r := 'ok:'||n; exception when others then r := sqlstate; end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return r;
end $$;

create function pg_temp.sees(u uuid, q text) returns int language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true);
  set local role authenticated;
  execute 'select count(*) from ' || q into n;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return n;
end $$;

insert into storage.buckets(id,name,public) values ('exercise-media','exercise-media',true),('coach-media','coach-media',true)
on conflict (id) do nothing;

-- Coaches A, B; admin M; client C (A's client), client D.
insert into auth.users(id,email) values
  ('a1990000-0000-0000-0000-0000000000a1','st-coach-a@local'),
  ('b1990000-0000-0000-0000-0000000000b1','st-coach-b@local'),
  ('e1990000-0000-0000-0000-0000000000e1','st-admin@local'),
  ('c1990000-0000-0000-0000-0000000000c1','st-client-c@local'),
  ('d1990000-0000-0000-0000-0000000000d1','st-client-d@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id in ('a1990000-0000-0000-0000-0000000000a1','b1990000-0000-0000-0000-0000000000b1');
update public.user_profiles set role='admin' where id='e1990000-0000-0000-0000-0000000000e1';

-- A's private exercise XA; a platform exercise XP (coach_id null).
insert into public.custom_exercises(id,coach_id,name,visibility) values
  ('a1990000-0000-0000-0000-00000000aaaa','a1990000-0000-0000-0000-0000000000a1','XA private','private'),
  ('f1990000-0000-0000-0000-00000000ffff',null,'XP platform','global');
-- Existing objects. Every destructive check has its own target, so no check's
-- outcome depends on another's.
insert into storage.objects(bucket_id,name,owner) values
  ('exercise-media','exercises/a1990000-0000-0000-0000-00000000aaaa/image.jpg','a1990000-0000-0000-0000-0000000000a1'),
  ('exercise-media','exercises/a1990000-0000-0000-0000-00000000aaaa/del_by_b.jpg','a1990000-0000-0000-0000-0000000000a1'),
  ('exercise-media','exercises/f1990000-0000-0000-0000-00000000ffff/image.jpg','a1990000-0000-0000-0000-0000000000a1'),
  ('exercise-media','exercises/f1990000-0000-0000-0000-00000000ffff/del_by_client.jpg','a1990000-0000-0000-0000-0000000000a1'),
  ('exercise-media','exercises/f1990000-0000-0000-0000-00000000ffff/del_by_coach.jpg','a1990000-0000-0000-0000-0000000000a1'),
  ('exercise-media','exercises/f1990000-0000-0000-0000-00000000ffff/del_by_admin.jpg','a1990000-0000-0000-0000-0000000000a1'),
  ('coach-media','coach-videos/a1990000-0000-0000-0000-0000000000a1/c1990000-0000-0000-0000-0000000000c1/1.mp4','a1990000-0000-0000-0000-0000000000a1'),
  ('coach-media','coach-transformations/a1990000-0000-0000-0000-0000000000a1/1.jpg','a1990000-0000-0000-0000-0000000000a1'),
  ('coach-media','coach-transformations/a1990000-0000-0000-0000-0000000000a1/2.jpg','a1990000-0000-0000-0000-0000000000a1');

do $$
declare r text;
  A constant uuid := 'a1990000-0000-0000-0000-0000000000a1';
  B constant uuid := 'b1990000-0000-0000-0000-0000000000b1';
  M constant uuid := 'e1990000-0000-0000-0000-0000000000e1';
  C constant uuid := 'c1990000-0000-0000-0000-0000000000c1';
  D constant uuid := 'd1990000-0000-0000-0000-0000000000d1';
  XA constant text := 'exercises/a1990000-0000-0000-0000-00000000aaaa/';
  XP constant text := 'exercises/f1990000-0000-0000-0000-00000000ffff/';
  ins constant text := 'insert into storage.objects(bucket_id,name,owner) values (%L,%L,%L)';
  upd constant text := 'update storage.objects set metadata=''{"x":1}'' where bucket_id=%L and name=%L';
  del constant text := 'delete from storage.objects where bucket_id=%L and name=%L';
begin
  -- ── exercise-media ───────────────────────────────────────────────────────
  r := pg_temp.run_as(C, format(ins, 'exercise-media', XP||'evil.jpg', C));
  insert into res values ('E1 a client cannot upload exercise media', r not like 'ok%', r);
  r := pg_temp.run_as(C, format(ins, 'exercise-media', 'anything/else.jpg', C));
  insert into res values ('E2 nobody uploads outside exercises/<existing exercise>/', r not like 'ok%', r);
  r := pg_temp.run_as(B, format(ins, 'exercise-media', XA||'image2.jpg', B));
  insert into res values ('E3 a coach cannot upload to another coach''s PRIVATE exercise', r not like 'ok%', r);
  r := pg_temp.run_as(B, format(upd, 'exercise-media', XA||'image.jpg'));
  insert into res values ('E4 a coach cannot overwrite another coach''s private exercise media', r <> 'ok:1', r);
  r := pg_temp.run_as(C, format(upd, 'exercise-media', XP||'image.jpg'));
  insert into res values ('E5 a client cannot overwrite platform exercise media', r <> 'ok:1', r);
  r := pg_temp.run_as(C, format(del, 'exercise-media', XP||'del_by_client.jpg'));
  insert into res values ('E6 a client cannot delete exercise media', r <> 'ok:1', r);
  r := pg_temp.run_as(B, format(del, 'exercise-media', XP||'del_by_coach.jpg'));
  insert into res values ('E7 a coach cannot delete shared platform media', r <> 'ok:1', r);
  r := pg_temp.run_as(B, format(del, 'exercise-media', XA||'del_by_b.jpg'));
  insert into res values ('E8 a coach cannot delete another coach''s exercise media', r <> 'ok:1', r);
  -- positive controls
  r := pg_temp.run_as(A, format(ins, 'exercise-media', XA||'video_front.mp4', A));
  insert into res values ('P1 the owning coach uploads to its private exercise', r = 'ok:1', r);
  r := pg_temp.run_as(A, format(upd, 'exercise-media', XA||'image.jpg'));
  insert into res values ('P2 the owning coach re-uploads (overwrites) its media', r = 'ok:1', r);
  r := pg_temp.run_as(B, format(ins, 'exercise-media', XP||'video_side.mp4', B));
  insert into res values ('P3 a coach attaches media to a platform exercise (update_exercise_media rule)', r = 'ok:1', r);
  r := pg_temp.run_as(M, format(upd, 'exercise-media', XA||'image.jpg'));
  insert into res values ('P4 an admin edits any exercise media', r = 'ok:1', r);
  r := pg_temp.run_as(M, format(del, 'exercise-media', XP||'del_by_admin.jpg'));
  insert into res values ('P5 an admin deletes platform media', r = 'ok:1', r);
  insert into res values ('P6 exercise media stays publicly readable',
    pg_temp.sees(D, 'storage.objects where bucket_id=''exercise-media''') >= 2, 'ok');

  -- ── coach-media ──────────────────────────────────────────────────────────
  r := pg_temp.run_as(C, format(ins, 'coach-media', 'coach-transformations/'||C||'/x.jpg', C));
  insert into res values ('M1 a client cannot upload to coach-media', r not like 'ok%', r);
  r := pg_temp.run_as(B, format(ins, 'coach-media', 'coach-transformations/'||A||'/fake.jpg', B));
  insert into res values ('M2 a coach cannot upload into another coach''s namespace', r not like 'ok%', r);
  r := pg_temp.run_as(B, format(upd, 'coach-media', 'coach-transformations/'||A||'/1.jpg'));
  insert into res values ('M3 a coach cannot overwrite another coach''s file', r <> 'ok:1', r);
  r := pg_temp.run_as(B, format(del, 'coach-media', 'coach-transformations/'||A||'/2.jpg'));
  insert into res values ('M4 a coach cannot delete another coach''s file', r <> 'ok:1', r);
  insert into res values ('M5 another client cannot list or sign a coach''s video to a client',
    pg_temp.sees(D, 'storage.objects where bucket_id=''coach-media'' and name like ''coach-videos/%''') = 0,
    'D_sees='||pg_temp.sees(D, 'storage.objects where bucket_id=''coach-media'' and name like ''coach-videos/%'''));
  insert into res values ('M6 another coach cannot list a coach''s video to a client',
    pg_temp.sees(B, 'storage.objects where bucket_id=''coach-media'' and name like ''coach-videos/%''') = 0, 'ok');
  -- positive controls
  r := pg_temp.run_as(A, format(ins, 'coach-media', 'voice/'||A||'/ex-1.m4a', A));
  insert into res values ('Q1 a coach uploads in its own namespace', r = 'ok:1', r);
  r := pg_temp.run_as(A, format(upd, 'coach-media', 'coach-transformations/'||A||'/1.jpg'));
  insert into res values ('Q2 a coach overwrites its own file', r = 'ok:1', r);
  insert into res values ('Q3 the coach and the named client read the video',
    pg_temp.sees(A, 'storage.objects where bucket_id=''coach-media'' and name like ''coach-videos/%''') = 1
    and pg_temp.sees(C, 'storage.objects where bucket_id=''coach-media'' and name like ''coach-videos/%''') = 1, 'ok');
  insert into res values ('Q4 transformations stay readable to signed-in users',
    pg_temp.sees(D, format('storage.objects where bucket_id=''coach-media'' and name=%L', 'coach-transformations/'||A||'/1.jpg')) = 1, 'ok');
  r := pg_temp.run_as(A, format(del, 'coach-media', 'voice/'||A||'/ex-1.m4a'));
  insert into res values ('Q5 a coach deletes its own file', r = 'ok:1', r);
end $$;

select case when ok then 'PASS' else 'FAIL' end || '|' || id || '|' || detail from res order by id;
rollback;
