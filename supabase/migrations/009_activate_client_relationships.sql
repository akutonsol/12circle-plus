-- Fix relationships that were set to 'pending' by the onboarding upsert
-- when the coach had is_accepting_clients = TRUE.
-- Going forward, the onboarding flow creates relationships as 'active' directly.

-- STAGE B.3 (B2-3/B2-4): user_profiles.is_accepting_clients is added by
-- migration 010, i.e. AFTER this file, so on a clean replay this statement
-- aborted 009. It is a ONE-TIME repair of rows the old onboarding upsert left
-- as 'pending'; a freshly rebuilt database has no such rows, so skipping it on
-- a clean replay is correct and needs no forward migration. Guarded on the
-- column's existence rather than reordered, so the statement still runs exactly
-- as before on any database that already has the column.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'user_profiles'
       AND column_name = 'is_accepting_clients'
  ) THEN
    UPDATE coach_client_relationships ccr
    SET
      status       = 'active',
      activated_at = COALESCE(activated_at, pending_at, NOW())
    FROM user_profiles coach_profile
    WHERE ccr.coach_id = coach_profile.id
      AND ccr.status   = 'pending'
      AND coach_profile.is_accepting_clients = TRUE;
  ELSE
    RAISE NOTICE '009: user_profiles.is_accepting_clients not present yet (added by 010) -- nothing to repair on a clean build';
  END IF;
END $$;
