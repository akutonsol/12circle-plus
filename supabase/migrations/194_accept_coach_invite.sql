-- Migration 194. A coach's invite can be accepted: accept_coach_invite(token).
-- And the commission source is derived from the VERIFIED account email.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["194"]. Applies after 193 (it relies on the
-- app.relationship_activation setting that 193's trigger reads).
--
-- OWNER DECISION (2026-11-15, Julia, in session; recorded in docs/decision-log.md):
-- "signing up from the invite link (matching email, unexpired, single use)
-- creates an active relationship marked coach-invited, at 0% commission. Paid
-- access then follows decision 1."
--
-- THE DEFECT. send-invite-email links to /#/signup?invite=<token>; nothing reads
-- the token, nothing checks expires_at, nothing sets accepted_at. An invite never
-- linked a client to the coach who sent it.
--
-- accept_coach_invite(p_token):
--   * the caller is signed in, and the invite is pending, unexpired, sent to the
--     caller's VERIFIED email (auth.users, not user_profiles.email, which the
--     client can rewrite), by a coach other than the caller;
--   * ONE refusal for every failure -- 42501 'invite not valid' -- so the function
--     is not an oracle for which tokens exist or whom they were sent to;
--   * the relationship (client = caller, coach = inviter) becomes 'active' with
--     initiated_by 'coach' (or keeps an existing row's provenance), activated_by
--     'invite' (193), and client_source 'coach_invited' through the source trigger;
--   * the invite is consumed (accepted, accepted_at) in the same transaction --
--     single use. Returns the coach's id.
--
-- ALSO FIXED HERE. set_relationship_client_source (040 / 113 / 192) decided
-- 'coach_invited' (0% commission) by matching coach_invites.invitee_email against
-- user_profiles.email -- a column authenticated users may UPDATE (verified on QA
-- 2026-11-15). A client could set its profile email to an address a coach had
-- invited and claim 0% commission. It now matches the verified auth.users email.
-- The 192 rules are otherwise unchanged.

BEGIN;

CREATE OR REPLACE FUNCTION public.set_relationship_client_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NOT NULL THEN
    -- Migration 192: a signed-in caller never chooses its own commission source,
    -- and a client never names its own price.
    IF NEW.client_id = v_uid AND NEW.monthly_price IS NOT NULL THEN
      RAISE EXCEPTION 'coach_client_relationships: monthly_price is set by the coach'
        USING ERRCODE = '42501';
    END IF;
    NEW.client_source := NULL;
  END IF;

  IF NEW.client_source IS NULL OR NEW.client_source = 'marketplace' THEN
    -- Migration 194: the client's VERIFIED email (auth.users), not the profile's.
    IF EXISTS (
      SELECT 1
        FROM coach_invites i
        JOIN auth.users u ON u.id = NEW.client_id
       WHERE i.coach_id = NEW.coach_id
         AND lower(i.invitee_email) = lower(u.email)
    ) THEN
      NEW.client_source := 'coach_invited';
    ELSE
      NEW.client_source := COALESCE(NEW.client_source, 'marketplace');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_relationship_client_source() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.accept_coach_invite(p_token text)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid   uuid := (SELECT auth.uid());
  v_email text;
  v_inv   public.coach_invites%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

  SELECT * INTO v_inv FROM public.coach_invites
   WHERE token = p_token
   FOR UPDATE;

  IF NOT FOUND
     OR v_inv.status IS DISTINCT FROM 'pending'
     OR (v_inv.expires_at IS NOT NULL AND v_inv.expires_at <= now())
     OR v_inv.coach_id IS NULL
     OR v_inv.coach_id = v_uid
     OR v_email IS NULL
     OR lower(v_inv.invitee_email) IS DISTINCT FROM v_email THEN
    RAISE EXCEPTION 'invite not valid' USING ERRCODE = '42501';
  END IF;

  -- Read by trg_relationship_activated_by (193): this activation is an invite.
  PERFORM set_config('app.relationship_activation', 'invite', true);

  INSERT INTO public.coach_client_relationships
         (client_id, coach_id, status, initiated_by, activated_at)
  VALUES (v_uid, v_inv.coach_id, 'active', 'coach', now())
  ON CONFLICT (client_id, coach_id) DO UPDATE
     SET status = 'active', activated_at = now()
   WHERE public.coach_client_relationships.status IS DISTINCT FROM 'active';

  PERFORM set_config('app.relationship_activation', '', true);

  UPDATE public.coach_invites
     SET status = 'accepted', accepted_at = now()
   WHERE id = v_inv.id;

  -- Both parties are told, durably (the app signs in and moves on; there is no
  -- screen to say it on).
  INSERT INTO public.notifications (recipient_id, type, title, body, data, read)
  VALUES
    (v_uid, 'invite_accepted', 'You''re connected with your coach',
     'You joined from your coach''s invite. Your coach can now see your progress.',
     jsonb_build_object('coach_id', v_inv.coach_id), false),
    (v_inv.coach_id, 'invite_accepted', 'Your invite was accepted',
     coalesce(nullif(trim((SELECT coalesce(first_name,'') || ' ' || coalesce(last_name,'')
                            FROM public.user_profiles WHERE id = v_uid)), ''), 'A client')
       || ' joined from your invite.',
     jsonb_build_object('client_id', v_uid), false);

  RETURN v_inv.coach_id;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_coach_invite(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_coach_invite(text) TO authenticated;

COMMENT ON FUNCTION public.accept_coach_invite(text) IS
  'Migration 194 (owner decision 2026-11-15): accept a pending, unexpired invite '
  'sent to the caller''s verified email by another user; activates the coach-client '
  'relationship (activated_by invite, client_source coach_invited) and consumes the '
  'invite. Every refusal is 42501 ''invite not valid''.';

COMMIT;
