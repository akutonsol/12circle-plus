-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 096 — Coaching Communication Engine (CCE) · Layer 8
--
-- Turns deterministic engine outputs into human communications. The engine
-- consumes ONLY deterministic outputs (weekly_feedback, program diff / decision
-- trace, predict_client, goal progress) — never raw data ad hoc — and assembles
-- a grounded BRIEF. A later LLM only phrases that brief (it performs no analysis
-- and may not add unsupported claims). Coach edits before sending.
--
-- Depends on 089/093/094/095. Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists communications (
  id           uuid primary key default gen_random_uuid(),
  subject_id   uuid references user_profiles(id),
  coach_id     uuid references user_profiles(id),
  program_id   uuid references workout_programs(id) on delete set null,
  type         text not null,          -- weekly_review | daily_brief | monthly_report | goal_review | risk_alert | celebration
  brief        jsonb not null,         -- the deterministic grounding packet
  source_refs  jsonb default '{}',     -- {prediction_id, trace_id, feedback_week, program_version}
  client_text  text,
  coach_text   text,
  llm_version  text,
  status       text not null default 'draft',   -- draft | approved | sent
  generated_at timestamptz default now(),
  approved_by  uuid references user_profiles(id),
  approved_at  timestamptz,
  sent_at      timestamptz
);
-- STAGE B.3 (B2-5): this index named created_at, which `communications` does not
-- have -- the table's timestamp is generated_at. The statement aborted 096 on a
-- clean replay, taking the rest of the communication engine with it. Left inert
-- here rather than silently rewritten; migration 111 creates the index on the
-- column that actually exists.
-- create index if not exists idx_comm_subject on communications(subject_id, created_at desc);
create index if not exists idx_comm_status  on communications(status);
alter table communications enable row level security;
drop policy if exists "comm read" on communications;
create policy "comm read" on communications for select to authenticated using (
  (subject_id = auth.uid() and status = 'sent')            -- clients see only sent
  or coach_id = auth.uid()
  or exists (select 1 from user_profiles where id = auth.uid() and role in ('admin','content_manager')));

-- ── Deterministic grounding packet for a weekly review ──────────────────────
create or replace function public.assemble_weekly_review(p_subject uuid, p_program uuid, p_week int)
returns jsonb language plpgsql stable security definer as $$
declare
  fb weekly_feedback%rowtype; prev weekly_feedback%rowtype;
  pred jsonb; regen jsonb; v_name text; v_rec_delta int; wins jsonb := '[]'::jsonb;
begin
  select * into fb from weekly_feedback where program_id = p_program and subject_id = p_subject and week = p_week;
  if not found then return jsonb_build_object('status','no_feedback','week',p_week); end if;
  select * into prev from weekly_feedback where program_id = p_program and subject_id = p_subject and week = p_week - 1;
  pred := public.predict_client(p_subject, p_program);
  select coalesce(first_name, 'Athlete') into v_name from user_profiles where id = p_subject;

  -- Latest regeneration for this program → "what changed and why".
  select jsonb_build_object('action', context->>'action', 'diff', result->'diff',
           'reason', (trace->0->>'reason'), 'rules', to_jsonb(rules_triggered))
    into regen from decision_traces
    where (context->>'type') = 'regeneration' and (context->>'program_id') = p_program::text
    order by created_at desc limit 1;

  v_rec_delta := case when prev.recovery is not null then fb.recovery - prev.recovery else null end;

  -- Deterministic "wins" (facts only — no interpretation).
  if coalesce(fb.prs,0) > 0 then wins := wins || to_jsonb(format('%s personal record(s)', fb.prs)); end if;
  if coalesce(fb.completion_pct,0) >= 90 then wins := wins || to_jsonb(format('%s%% workout completion', fb.completion_pct)); end if;
  if coalesce(v_rec_delta,0) > 0 then wins := wins || to_jsonb(format('recovery up %s points', v_rec_delta)); end if;

  return jsonb_build_object(
    'status','ok','type','weekly_review','client_name',v_name,'week',p_week,
    'week_summary', jsonb_build_object('completion', fb.completion_pct, 'recovery', fb.recovery,
      'energy', fb.energy, 'prs', fb.prs, 'pain', fb.pain, 'recovery_delta', v_rec_delta),
    'wins', wins,
    'program_changes', coalesce(regen, jsonb_build_object('action','none')),
    'goal_progress', pred->'goal',
    'predictions', jsonb_build_object('plateau', pred->'plateau_risk',
      'injury', pred->'injury_risk', 'recovery', pred->'recovery', 'alerts', pred->'alerts'),
    'source_refs', jsonb_build_object('feedback_week', p_week, 'program_id', p_program));
end;
$$;
grant execute on function public.assemble_weekly_review(uuid, uuid, int) to authenticated;

-- Create a weekly-review communication row (brief assembled; text filled by the
-- generate-communication edge fn or the coach). Coach-scoped.
create or replace function public.create_weekly_review(p_subject uuid, p_program uuid, p_week int)
returns jsonb language plpgsql security definer as $$
declare v_brief jsonb; v_id uuid; v_coach uuid;
begin
  v_brief := public.assemble_weekly_review(p_subject, p_program, p_week);
  if v_brief->>'status' <> 'ok' then return v_brief; end if;
  select coach_id into v_coach from workout_programs where id = p_program;
  insert into communications(subject_id, coach_id, program_id, type, brief, source_refs, status)
  values (p_subject, coalesce(v_coach, auth.uid()), p_program, 'weekly_review',
          v_brief, v_brief->'source_refs', 'draft')
  returning id into v_id;
  return v_brief || jsonb_build_object('communication_id', v_id);
end;
$$;
grant execute on function public.create_weekly_review(uuid, uuid, int) to authenticated;

-- Coach edits the drafted text.
create or replace function public.update_communication(p_id uuid, p_client_text text, p_coach_text text)
returns void language plpgsql security definer as $$
begin
  update communications set client_text = p_client_text, coach_text = p_coach_text
  where id = p_id and (coach_id = auth.uid()
    or exists (select 1 from user_profiles where id = auth.uid() and role in ('admin','content_manager')));
end;
$$;
grant execute on function public.update_communication(uuid, text, text) to authenticated;

-- Send (client can now see it). Coach-controlled.
create or replace function public.send_communication(p_id uuid)
returns void language plpgsql security definer as $$
begin
  update communications set status = 'sent', approved_by = auth.uid(),
    approved_at = now(), sent_at = now()
  where id = p_id and (coach_id = auth.uid()
    or exists (select 1 from user_profiles where id = auth.uid() and role in ('admin','content_manager')));
end;
$$;
grant execute on function public.send_communication(uuid) to authenticated;
