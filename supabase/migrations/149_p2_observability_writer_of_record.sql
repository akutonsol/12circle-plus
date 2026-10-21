-- Migration 149 — P2 · the observability population gets a definer write path,
--                      so `service_role` stops being its writer of record.
--
-- WHY. §8.16·Q4, answered at §19.3, is explicit about the terms:
--
--   "THE DEFERRAL IS DISCHARGED FOR THE OBSERVABILITY POPULATION **ON THE SAME
--    TERMS AS THE AUDIT POPULATIONS** — service_role is NOT the writer of record."
--
-- Migration 148 revoked `service_role`'s direct INSERT on all three audit
-- populations, leaving their writes to `SECURITY DEFINER` functions owned by the
-- table owner -- and then GRANTED `service_role` a direct INSERT on
-- `observability_events`. Those are not the same terms. With a direct grant the
-- emitting tier IS the writer of record, which is the one thing §8.16·Q4 says it
-- is not. Caught by re-reading the ruling against 148, not by a failing test.
--
-- WHAT THIS IS NOT. It introduces no new authorization boundary and asks no
-- unanswered question. The emitting tier is unchanged -- `service_role` still
-- emits telemetry -- and only the ROUTE changes, from a table grant to a definer
-- function. That is the same correction 148 made for the audit populations,
-- applied where it was missed.
--
-- The Incident population is deliberately NOT given the same treatment: there the
-- missing write path turns on WHO MAY OPEN AN INCIDENT, which no ruling answers
-- (V5 §81.2). Here there is no such question -- machine telemetry has no
-- authorization subject -- so the path is derivable and the boundary is not.

CREATE OR REPLACE FUNCTION public.observability_record(
  p_component       text,
  p_retention_class text,
  p_correlation_id  uuid    DEFAULT NULL,
  p_payload         jsonb   DEFAULT NULL
) RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  INSERT INTO public.observability_events
    (component, retention_class, correlation_id, payload)
  VALUES
    (p_component, p_retention_class, p_correlation_id, p_payload);
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  -- Best-effort, on A3 sub-ruling 4's reasoning: telemetry must never abort the
  -- operation it describes. As in audit_record_event(), the WARNING is an
  -- operational signal and NOT a record -- A2 ruled a server-log line does not
  -- satisfy an audit obligation.
  RAISE WARNING 'observability_record failed (component=%): % [%]',
    p_component, SQLERRM, SQLSTATE;
  RETURN false;
END;
$$;
ALTER FUNCTION public.observability_record(text, text, uuid, jsonb) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.observability_record(text, text, uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.observability_record(text, text, uuid, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.observability_record(text, text, uuid, jsonb) TO service_role;

-- The direct grant 148 left in place. Removing it is the whole point: after this,
-- `service_role` can cause a record to exist but is not the party that wrote it.
REVOKE INSERT ON TABLE public.observability_events FROM service_role;

COMMENT ON FUNCTION public.observability_record(text, text, uuid, jsonb) IS
  '§8.16·Q4 — the observability population''s write path, so service_role is NOT its writer of '
  'record, "on the same terms as the audit populations". Best-effort per A3 sub-ruling 4''s '
  'reasoning. The CHECK constraints still bind: a 90-day class cannot attach to an audit-worthy '
  'component and vice versa (§8.16·Q2), and the freeze trigger binds this function exactly as it '
  'binds any caller (§8.16·Q1 — identity and occurrence immutable, payload write-once). '
  'DML-DEEP ONLY: §8.19 declined the anchor, so this is not a tamper-resistance claim.';
