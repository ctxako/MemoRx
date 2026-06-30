-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- admin_reset_cycle: clears all future challenge slots and shuffles a fresh
-- cycle queue starting from tomorrow. Today's drug is preserved (locked).
-- Only callable via service_role (admin proxy).

CREATE OR REPLACE FUNCTION public.admin_reset_cycle()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := current_challenge_date();
BEGIN
  -- Wipe every future assignment; today and past stay locked
  DELETE FROM daily_challenges WHERE challenge_date > v_today;

  -- Fresh random shuffle of ALL drugs into the queue
  UPDATE app_settings
  SET value = (SELECT jsonb_agg(id ORDER BY random()) FROM drugs)
  WHERE key = 'challenge_cycle_remaining';

  RETURN jsonb_build_object('ok', true, 'reset_date', v_today);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reset_cycle() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reset_cycle() TO service_role;
