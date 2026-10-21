-- Simulated fix (never applied anywhere): require an active coaching relationship.
create or replace function public.assign_nutrition_plan(p_client_id uuid, p_calories_target integer, p_protein_g integer,
  p_carbs_g integer, p_fat_g integer, p_water_target_oz integer default null, p_notes text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_coach uuid := (select auth.uid()); v_id uuid;
begin
  if v_coach is null then raise exception 'not authenticated' using errcode = '42501'; end if;
  if not public.is_active_coach_of(p_client_id) then raise exception 'not authorized' using errcode = '42501'; end if;
  update public.client_nutrition_plans set is_active = false where client_id = p_client_id and is_active;
  insert into public.client_nutrition_plans(client_id, coach_id, calories_target, protein_g, carbs_g, fat_g, water_target_oz, notes, is_active)
  values (p_client_id, v_coach, p_calories_target, p_protein_g, p_carbs_g, p_fat_g, p_water_target_oz, p_notes, true) returning id into v_id;
  return v_id;
end $$;
