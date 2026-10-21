-- Regression: every function in `public` carries a pinned search_path.
--
-- Pins the posture migration 116 §1 (SECURITY DEFINER) and 118 F-08 (the rest)
-- established, which Phase 2 migrations 119/120/121 silently dropped and 122
-- restored. `SET search_path` is part of a function's DEFINITION, not a grant:
-- ACLs and ownership survive CREATE OR REPLACE, proconfig does not. Every
-- assertion below FAILED against QA before migration 122.
--
-- A definer function with a mutable search_path resolves unqualified names
-- through the CALLER's search_path, so a caller who can create objects in a
-- schema earlier on that path can shadow a table or operator and have it
-- executed with the definer's rights.
--
-- Runs inside one DO block that ends by raising, so it ALWAYS ROLLS BACK.
--
--   supabase db query --linked --file supabase/tests/security/function-search-path.sql
--
-- QA only. A run containing `FAIL` anywhere is a failing suite.

do $$
declare
  v_res  text := '';
  v_n    int;
  v_list text;
begin
  -- SP-1 — no SECURITY DEFINER function may resolve names through the caller.
  select count(*), coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.proname), '—')
    into v_n, v_list
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and not exists (
       select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' SP-1  unpinned SECURITY DEFINER functions: ' || v_n || ' — ' || v_list || E'\n';

  -- SP-2 — 118 F-08 extended it to every function, definer or not.
  select count(*), coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.proname), '—')
    into v_n, v_list
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prokind = 'f'
     and not exists (
       select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' SP-2  unpinned functions of any kind: ' || v_n || ' — ' || v_list || E'\n';

  -- SP-3 — the pin is the one Phase 1 chose, not some other path.
  select count(*) into v_n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prokind = 'f'
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
     and not exists (
       select 1 from unnest(coalesce(p.proconfig, '{}')) c
        where c = 'search_path=public, pg_temp' or c = 'search_path=public,pg_temp'
           or c = 'search_path=""' or c like 'search_path=public%');
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' SP-3  functions pinned to a path other than public: ' || v_n || E'\n';

  -- SP-4 — the two functions the Phase 2 drift actually unpinned, named.
  select count(*) into v_n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('generate_client_plan', 'materialize_program_week')
     and p.prosecdef
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  v_res := v_res || case when v_n = 2 then 'PASS' else 'FAIL' end
    || ' SP-4  generate_client_plan + materialize_program_week re-pinned: ' || v_n || '/2' || E'\n';

  -- SP-5 — the re-pin changed no grant: EXECUTE is still closed to anon/PUBLIC.
  select count(*) into v_n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace,
         aclexplode(p.proacl) a
   where ns.nspname = 'public'
     and (a.grantee = 0 or a.grantee = 'anon'::regrole::oid)
     and a.privilege_type = 'EXECUTE';
  v_res := v_res || case when v_n = 0 then 'PASS' else 'FAIL' end
    || ' SP-5  EXECUTE grants to PUBLIC or anon: ' || v_n || E'\n';

  raise exception E'\n=== FUNCTION SEARCH PATH ===\n%', v_res;
end;
$$;
