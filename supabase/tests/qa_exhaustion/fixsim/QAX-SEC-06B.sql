-- Simulated fix B — CONTENT-EDITOR-ONLY access to the certification path.
-- The alternative to QAX-SEC-06A.sql. Both exist because the choice is an OWNER
-- DECISION entangled with PD-A02 (Proceed? = No), which proposes gating the ENGINE
-- on exercise_certifications.<module>. Nothing here selects between A and B.
--
-- Rule: only admin / content_manager may read certification data at all
-- (public.is_content_editor(), 083:86-89 — the DB's own definition of "may edit
-- content", which deliberately EXCLUDES the self-selectable `coach` role, 115:326).
--
-- EXPECTED CONSEQUENCE, stated rather than discovered: POS-06A and POS-06D FAIL
-- under this option — a coach loses sight of the certification state of their OWN
-- exercise. That is the real cost of content-editor-only scoping, and it is the
-- central reason this needs an owner rather than an engineer.
alter view public.exercise_certifications rename to exercise_certifications_unscoped;
create view public.exercise_certifications as
  select * from public.exercise_certifications_unscoped z
   where public.is_content_editor() or public.is_admin();
revoke all on public.exercise_certifications from public, anon;
grant select on public.exercise_certifications to authenticated;   -- mirrors 112:48
revoke all on public.exercise_certifications_unscoped from public, anon, authenticated;

create or replace function public.exercise_certification(p_id uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select to_jsonb(c) from public.exercise_certifications c
   where c.id = p_id and (public.is_content_editor() or public.is_admin());
$$;

-- certification_summary() untouched on purpose: 117:328 already guards it with
-- require_content_editor(), and under this option an entitled caller sees every row
-- through the predicated view, so the engine needs no change and POS-06C still holds.
