-- 126_parq_risk_flag_typed_append.sql
--
-- Closes F-J-17: a member cannot save a required PAR-Q safety declaration.
--
-- ── ROOT CAUSE ──────────────────────────────────────────────────────────────
-- migration 115 declares, inside public.derive_parq_risk():
--
--     v_flags text[] := '{}';
--     ...
--     v_flags := v_flags || v_labels[i];      -- WORKS: v_labels[i] is typed text
--     ...
--     v_flags := v_flags || 'pregnancy';      -- THROWS 22P02
--     v_flags := v_flags || 'postpartum';     -- THROWS 22P02
--     v_flags := v_flags || 'active_injuries';-- THROWS 22P02
--
-- `text[] || <untyped literal>` is ambiguous. PostgreSQL resolves it to
-- anyarray || anyarray, then tries to read 'pregnancy' AS AN ARRAY LITERAL and
-- fails with 22P02 malformed array literal: "pregnancy". The loop-driven append
-- two lines above is unambiguous because v_labels[i] is a declared text value —
-- which is why the fault hides: only the three hand-written literals throw.
--
-- ── WHY IT BLOCKS A WRITE RATHER THAN LOSING A FLAG ─────────────────────────
-- public.apply_parq_risk() is a BEFORE INSERT OR UPDATE trigger on
-- public.user_profiles (migration 115). The classifier runs inside the write
-- path, so the throw rejects the entire row. A member therefore cannot record:
--
--     * an active injury           (has_injuries + injury_locations)
--     * a pregnancy                (medical_conditions LIKE '%Pregnancy%')
--     * a postpartum state         (medical_conditions LIKE '%Postpartum%')
--
-- The fix that made risk server-authoritative made risk unrecordable. That
-- BEFORE-trigger design is correct (Phase 0 Q-4: the member owns the answers,
-- the server owns the classification) and is preserved unchanged here.
--
-- ── THE CORRECTION ──────────────────────────────────────────────────────────
-- Cast the three literals to ::text so the append resolves to
-- anyarray || anyelement, exactly as the loop-driven append already does.
-- Nothing else changes:
--
--   * the flag vocabulary and its order are byte-identical to 115;
--   * risk_flags remains the comma-joined TEXT contract
--     (array_to_string(v_flags, ',')), matching user_profiles.risk_flags TEXT
--     from migration 013 and IntakeData.riskFlags.join(',') in
--     apps/mobile/lib/features/onboarding/domain/intake_data.dart;
--   * the signature, IMMUTABLE volatility and pinned search_path are restated
--     verbatim. CREATE OR REPLACE does NOT preserve proconfig, so the pin is
--     re-declared here on purpose (I-MIG-03 / CRC-07);
--   * EXECUTE privileges are preserved by CREATE OR REPLACE (same oid);
--   * no column, policy, grant or trigger is altered.
--
-- No schema change is required: this is a function-body defect only.
--
-- The sibling defect F-J-07 (build_workout appends 'RECOVERY_REDUCTION' the
-- same way) is DELIBERATELY OUT OF SCOPE and is not touched here.
--
-- Forward-only. Idempotent: CREATE OR REPLACE.

BEGIN;

CREATE OR REPLACE FUNCTION public.derive_parq_risk(
  p_parq                jsonb,
  p_medical_conditions  text,
  p_has_injuries        boolean,
  p_injury_locations    text
)
RETURNS TABLE (risk_score integer, risk_level text, risk_flags text)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_parq  jsonb := COALESCE(p_parq, '{}'::jsonb);
  v_med   text  := COALESCE(p_medical_conditions, '');
  v_score int;
  v_level text;
  v_flags text[] := '{}';
  -- PAR-Q question number -> flag label, in question order.
  v_labels constant text[] := ARRAY[
    'heart_condition',            -- 1
    'chest_pain_exercise',        -- 2
    'chest_pain_rest',            -- 3
    'fainting_dizziness',         -- 4
    'orthopedic_condition',       -- 5
    'bp_heart_medication',        -- 6
    'doctor_advised_no_exercise', -- 7
    'other_medical_reason'        -- 8
  ];
  i int;
BEGIN
  SELECT count(*) INTO v_score
    FROM jsonb_each(v_parq) AS e(k, v)
   WHERE e.v = 'true'::jsonb;

  -- Q1 heart condition, Q2 chest pain on exertion, Q3 chest pain at rest,
  -- Q4 fainting / dizziness, Q7 doctor advised against unsupervised exercise.
  IF (SELECT bool_or(v_parq ->> q = 'true')
        FROM unnest(ARRAY['1', '2', '3', '4', '7']) AS q) THEN
    v_level := 'high';
  ELSIF v_score > 0
     OR v_med LIKE '%Pregnancy%'
     OR v_med LIKE '%Heart Disease%'
     OR v_med LIKE '%High Blood Pressure%' THEN
    v_level := 'moderate';
  ELSE
    v_level := 'low';
  END IF;

  FOR i IN 1 .. array_length(v_labels, 1) LOOP
    IF v_parq ->> i::text = 'true' THEN
      v_flags := v_flags || v_labels[i];
    END IF;
  END LOOP;
  -- F-J-17: these three appends are the whole defect. The ::text cast makes the
  -- operator anyarray || anyelement instead of anyarray || anyarray.
  IF v_med LIKE '%Pregnancy%'  THEN v_flags := v_flags || 'pregnancy'::text;  END IF;
  IF v_med LIKE '%Postpartum%' THEN v_flags := v_flags || 'postpartum'::text; END IF;
  IF COALESCE(p_has_injuries, false) AND COALESCE(p_injury_locations, '') <> '' THEN
    v_flags := v_flags || 'active_injuries'::text;
  END IF;

  RETURN QUERY SELECT v_score, v_level, array_to_string(v_flags, ',');
END;
$$;

COMMENT ON FUNCTION public.derive_parq_risk(jsonb, text, boolean, text) IS
  'Authoritative PAR-Q risk classification (Phase 0 Q-4). Pure function of the '
  'member''s answers. The member owns the answers; the server owns the '
  'classification -- a safety constraint the constrained party can overwrite is '
  'not a constraint. Mirrors IntakeData.riskLevel in intake_data.dart. '
  'Migration 126 (F-J-17) casts the pregnancy / postpartum / active_injuries '
  'appends to ::text; before that the BEFORE trigger raised 22P02 and no member '
  'could save those declarations.';

COMMIT;
