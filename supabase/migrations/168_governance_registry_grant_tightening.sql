-- ═══════════════════════════════════════════════════════════════════════════
-- 168 · THE REGISTRY HELD A DELETE GRANT NOBODY SHOULD HAVE
--
-- Found while verifying 167. A trust_lead's DELETE against governance_policy
-- returned 204 and the row SURVIVED — RLS held, because 154's write policy is
-- `FOR ALL USING (is_admin())` and that covers DELETE. Correct outcome.
--
-- But the TABLE GRANT is wrong underneath it. 154 revoked only from `anon`:
--
--     REVOKE ALL ON TABLE public.governance_policy FROM anon;        -- 154:156
--
-- so `authenticated` still carries Supabase's default `GRANT ALL`, DELETE
-- included, and RLS is the ONLY thing standing between a member and a deleted
-- governance record. That is the same shape as V5 §129.2, where three views were
-- born holding `authenticated` write grants: not exploitable while the policy
-- holds, and one policy edit away from being so.
--
-- THE APPROVED MATRIX HAS NO DELETE VERB FOR THIS AREA. A privilege that no grant
-- in the matrix corresponds to should not exist, whatever RLS currently does with
-- it. Defence in depth is the point: 129.2's escalation landed on the one table
-- whose protection was RLS alone, and survived on the one that also had a trigger.
--
-- REVOKE ALL then GRANT precisely, which is 118's pattern (118:106, 118:119).
-- SELECT stays (163's read arm), INSERT and UPDATE stay (167's authoring arms).
-- DELETE, TRUNCATE, REFERENCES and TRIGGER go.
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['governance_policy', 'governance_policy_version',
                           'governance_policy_rule', 'governance_policy_set',
                           'governance_policy_set_member'] LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE public.%I TO authenticated', t);
  END LOOP;
END $$;
