-- Fix: archive_and_reset_weekly_xp() queried leaderboard_public view which
-- returns md5-surrogate IDs under service_role/cron (auth.uid() = NULL),
-- resulting in zero rows archived. Now queries public.users directly.
--
-- Fix: maybe_reset_weekly_xp() zeroed weekly_xp without archiving first,
-- racing with archive_and_reset_weekly_xp() via shared weekly_reset_last guard.
-- Now delegates to archive_and_reset_weekly_xp() so the hot path archives-then-zeros.

CREATE OR REPLACE FUNCTION public.archive_and_reset_weekly_xp()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today      date := current_challenge_date();
  v_last_reset date;
  v_week_start date;
BEGIN
  -- Lock the guard row to prevent concurrent execution
  SELECT (value #>> '{}')::date INTO v_last_reset
    FROM app_settings
   WHERE key = 'weekly_reset_last'
     FOR UPDATE;

  IF EXTRACT(DOW FROM v_today) <> 1 OR v_today <= v_last_reset THEN
    RETURN;
  END IF;

  v_week_start := v_today - 7;

  -- Snapshot from users directly (not the leaderboard_public view).
  -- Named-users-only: has XP, has a real display_name.
  INSERT INTO public.weekly_results (user_id, week_start_date, rank, xp)
  SELECT
    u.id,
    v_week_start,
    RANK() OVER (ORDER BY u.weekly_xp DESC),
    u.weekly_xp
  FROM public.users u
  WHERE u.weekly_xp >= 1
    AND u.display_name IS NOT NULL
    AND lower(btrim(u.display_name::text)) NOT LIKE '%signed out%'
  ON CONFLICT (user_id, week_start_date) DO NOTHING;

  UPDATE public.users SET weekly_xp = 0;

  UPDATE app_settings
     SET value = to_jsonb(v_today::text)
   WHERE key = 'weekly_reset_last';
END;
$$;

CREATE OR REPLACE FUNCTION public.maybe_reset_weekly_xp()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM archive_and_reset_weekly_xp();
END;
$$;

-- Preserve existing grants: only postgres + service_role
REVOKE EXECUTE ON FUNCTION public.archive_and_reset_weekly_xp() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.maybe_reset_weekly_xp() FROM PUBLIC, anon, authenticated;
