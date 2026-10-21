-- ═══════════════════════════════════════════════════════════════════════════
-- 177 · the coach approval matrix must not be bypassed by an UNKNOWN coaching mode
--
-- D17 established that `evaluate_week` returns `needs_approval = NULL` -- not false and
-- not true -- when the subject's coaching mode cannot be established. That is SQL
-- three-valued logic: `(NULL = 'coach_guided' and action <> 'CONTINUE')` is NULL, and
-- `NULL or false` is NULL. Every consumer treats null as falsy, so the change
-- AUTO-APPLIES.
--
-- V5 §171.5 recorded that as an owner question. IT IS NOT ONE. The governing record
-- answers it, and §172's own citation is where the answer was sitting:
--
--   * `product-bible.md:111` -- AI may NOT "Bypass the coach approval matrix for
--     coach-guided clients.";
--   * `product-bible.md:54`  -- AI "steps back for the human on anything consequential";
--   * `product-bible.md:116` -- AI may NOT "Make a claim it cannot ground; if data is
--     missing, it says so.";
--   * `decision-log.md:18`   -- "Coaches approve consequential changes (approval matrix
--     by mode). ... Minor changes auto-apply **for AI/self-guided** to avoid friction.";
--   * `MASTER_PRODUCT_DECISIONS:63` -- on this very function: an unwritten
--     `subject_id` "silently disables the approval matrix, which is a HARD-CONSTRAINT
--     VIOLATION, not a feature gap. No decision needed; it is a P0 defect."
--
-- Auto-apply is licensed for `self_guided` and `ai_guided` and for nothing else. An
-- unestablished mode cannot license it, and proceeding without sign-off risks exactly
-- the bypass :111 forbids -- because a client whose mode is unknown MAY be coach-guided.
-- So this is the same hard-constraint violation ENG-02 was, one layer down, and it is
-- fixed rather than escalated.
--
-- EXACTLY ONE CASE CHANGES:
--   unknown mode + a non-CONTINUE action + no injury rule
--     before: NULL -> falsy -> applied without sign-off
--     after : true -> requires sign-off
-- coach_guided, self_guided, ai_guided and the injury arm are untouched, and `CONTINUE`
-- already evaluated to false because `NULL and false` is false.
--
-- The body below is migration 127's, reproduced programmatically rather than retyped,
-- with that single expression replaced. `SET search_path` is restated, as I-MIG-03 /
-- CRC-07 require of any CREATE OR REPLACE.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.evaluate_week_engine(p_program_id uuid, p_week int)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  fb weekly_feedback%rowtype; v_mode text; v_dur int; v_focus_injury boolean;
  action text := 'CONTINUE'; vol_delta numeric := 0; rules text[] := '{}';
  escalate boolean := false; needs_approval boolean := false; reason text := 'on track';
begin
  select * into fb from weekly_feedback where program_id = p_program_id and week = p_week;
  if not found then return jsonb_build_object('action', 'NO_FEEDBACK'); end if;
  select (plan->>'duration_weeks')::int into v_dur from workout_programs where id = p_program_id;
  select coaching_mode into v_mode from user_profiles where id = fb.subject_id;
  v_focus_injury := coalesce(jsonb_array_length(fb.pain), 0) > 0;

  -- Priority order: injury → fatigue deload → recovery → adherence → overload.
  if v_focus_injury then
    action := 'REPLACE_EXERCISES'; rules := rules || 'INJURY_ADAPTATION'::text;
    reason := 'pain reported — substitute via movement graph';
  elsif fb.recovery is not null and fb.recovery < 55 and coalesce(fb.energy, 100) < 50 then
    action := 'INSERT_DELOAD'; rules := rules || 'FATIGUE_DELOAD'::text; reason := 'accumulated fatigue';
  elsif fb.recovery is not null and fb.recovery < 60 then
    action := 'REDUCE_VOLUME'; vol_delta := -0.10;
    rules := rules || array['RECOVERY_PROTECTION', 'REPLACE_HIGH_FATIGUE']; reason := 'low recovery';
  elsif fb.completion_pct is not null and fb.completion_pct < 60 then
    action := 'REDUCE_COMPLEXITY'; rules := rules || 'ADHERENCE_SUPPORT'::text;
    escalate := true; reason := 'low adherence';
  elsif fb.recovery is not null and fb.recovery > 85
        and fb.completion_pct is not null and fb.completion_pct > 90 then
    action := 'INCREASE_VOLUME'; vol_delta := 0.05;
    rules := rules || 'PROGRESSIVE_OVERLOAD'::text; reason := 'recovered + high completion';
  end if;

  -- Coach approval matrix: coach-guided approves any change; injury needs
  -- approval in every mode; otherwise minor changes are automatic.
  -- 177 · FAIL CLOSED WHEN THE MODE IS NOT ESTABLISHED. See the migration header.
  -- Auto-apply is licensed only for the two modes decision-log.md names; anything
  -- else -- coach_guided, or a mode that could not be established -- needs sign-off
  -- for a consequential action. `coalesce` also makes the result a TOTAL boolean:
  -- the previous expression returned NULL whenever v_mode was NULL.
  needs_approval := (action <> 'CONTINUE'
                     and coalesce(v_mode, '') not in ('self_guided', 'ai_guided'))
                    or (rules && array['INJURY_ADAPTATION']);

  return jsonb_build_object(
    'week', p_week, 'action', action, 'volume_delta', vol_delta,
    'rules_triggered', to_jsonb(rules), 'escalate', escalate,
    'needs_approval', needs_approval, 'coaching_mode', coalesce(v_mode, 'unknown'),
    'affected_weeks', case when p_week < v_dur
        then jsonb_build_array(p_week + 1, v_dur) else jsonb_build_array() end,
    'reason', reason);
end;
$$;

COMMENT ON FUNCTION public.evaluate_week_engine(uuid, integer) IS
  'V5 §175 · the 127 body with one change: needs_approval is a TOTAL boolean and fails '
  'CLOSED when the coaching mode cannot be established. Auto-apply is licensed only for '
  'self_guided and ai_guided (decision-log.md:18); an unknown mode may be coach-guided, '
  'and applying a consequential change without sign-off would bypass the approval '
  'matrix that product-bible.md:111 forbids bypassing.';
