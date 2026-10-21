-- 134_search_path_pin_canonical_form.sql
--
-- V5 SECURITY FOUNDATION — WAVE 1, repository-form correction.
--
-- Migration number 134 assigned at wave entry per docs/MASTER_REMEDIATION_WAVES.md
-- section 0.2.  Forward-only: migration 132 is applied and committed and is NOT
-- edited here, per the rule I-MIG-03 itself states -- "Carry the property forward
-- in a NEW migration - never by editing history."  This mirrors what migration
-- 122 did for the 119/120/121 drift.
--
-- ===========================================================================
-- WHY
-- ===========================================================================
--
-- I-MIG-03 reported two durability violations against migration 132:
--
--     [VIOLATION] is_team_lead_of(search_path pin)  established 102 -> stripped 132
--     [VIOLATION] may_notify(search_path pin)       established 129 -> stripped 132
--
-- The EFFECTIVE property was never lost.  The live catalog holds
-- `search_path=public` on is_team_lead_of and `search_path=public, pg_temp` on
-- may_notify, and zero SECURITY DEFINER functions in `public` carry a mutable
-- search_path.  What migration 132 got wrong was the FORM: it reproduced the
-- definitions from `pg_get_functiondef()`, which normalises the clause to
--
--     SET search_path TO 'public', 'pg_temp'
--
-- whereas this repository's migrations write the canonical
--
--     SET search_path = public, pg_temp
--
-- (102, 122, 129).  I-MIG-03 matches the canonical literal, so it read the
-- normalised rendering as a strip.  SEC-028 matches either form and stayed
-- green -- two guards, different strictness on one clause, which is why this
-- surfaced only once QAT-1 let the job reach step 3.
--
-- ===========================================================================
-- WHAT THIS DOES NOT DO
-- ===========================================================================
--
-- Nothing but re-state the two functions in canonical form.  Bodies, arguments,
-- return types, volatility, SECURITY DEFINER, the D1(ii) lifecycle predicate
-- (`status = 'active'`) and every authorization decision are reproduced
-- verbatim from 132.
--
-- Note the two pins differ, deliberately.  `is_team_lead_of` was established by
-- 102 as `= public`; `may_notify` by 129 as `= public, pg_temp`.  Each keeps the
-- value its establishing migration set.  Writing `= public, pg_temp` for
-- is_team_lead_of would ADD pg_temp to its effective search_path -- a real
-- change to a security property, which is precisely what this migration exists
-- to avoid.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_team_lead_of(target_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.coach_team_members t
    WHERE t.coach_id  = auth.uid()
      AND t.member_id = target_user
      -- D1(ii): only ACTIVE membership satisfies team-lead authorization.
      AND t.status    = 'active'
  );
$function$;

CREATE OR REPLACE FUNCTION public.may_notify(recipient uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
  SELECT (SELECT auth.uid()) IS NULL
      OR recipient = (SELECT auth.uid())
      OR EXISTS (SELECT 1 FROM public.coach_client_relationships r
                  WHERE (r.coach_id  = (SELECT auth.uid()) AND r.client_id = recipient)
                     OR (r.client_id = (SELECT auth.uid()) AND r.coach_id  = recipient))
      OR public.shares_conversation_with(recipient)
      OR EXISTS (SELECT 1 FROM public.coaching_calls c
                  WHERE (c.coach_id  = (SELECT auth.uid()) AND c.client_id = recipient)
                     OR (c.client_id = (SELECT auth.uid()) AND c.coach_id  = recipient))
      -- WAVE 1 (D1(ii)): only an ACTIVE membership creates a notify channel.
      OR EXISTS (SELECT 1 FROM public.coach_team_members t
                  WHERE t.status = 'active'
                    AND ((t.coach_id  = (SELECT auth.uid()) AND t.member_id = recipient)
                      OR (t.member_id = (SELECT auth.uid()) AND t.coach_id  = recipient)))
      -- I-NOT-02 arm 1: the recipient authored a post the caller has commented
      -- on. Both sides are required -- authorship alone does not qualify, and
      -- neither does commenting on somebody else's post.
      OR EXISTS (SELECT 1 FROM public.community_posts p
                   JOIN public.post_comments pc ON pc.post_id = p.id
                  WHERE p.user_id  = recipient
                    AND pc.user_id = (SELECT auth.uid()))
      -- I-NOT-02 arm 2: the recipient and the caller are both booked into the
      -- same class. Status is deliberately not filtered: the writer this arm
      -- exists for is _promoteFromWaitlist, reached from cancelBooking, where
      -- the caller's own booking has just been set to 'cancelled'.
      OR EXISTS (SELECT 1 FROM public.class_bookings cb_self
                   JOIN public.class_bookings cb_other
                     ON cb_other.class_id = cb_self.class_id
                  WHERE cb_self.user_id  = (SELECT auth.uid())
                    AND cb_other.user_id = recipient);
$function$;

COMMIT;
