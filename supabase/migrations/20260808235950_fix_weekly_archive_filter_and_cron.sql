-- Drop the display_name filter from archive_and_reset_weekly_xp().
-- weekly_xp >= 1 is sufficient to scope to active players.
-- Also tighten the cron from */2 8-12 to a single fire at 08:00 UTC Monday.

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
  SELECT (value #>> '{}')::date INTO v_last_reset
    FROM app_settings
   WHERE key = 'weekly_reset_last'
     FOR UPDATE;

  IF EXTRACT(DOW FROM v_today) <> 1 OR v_today <= v_last_reset THEN
    RETURN;
  END IF;

  v_week_start := v_today - 7;

  INSERT INTO public.weekly_results (user_id, week_start_date, rank, xp)
  SELECT
    u.id,
    v_week_start,
    RANK() OVER (ORDER BY u.weekly_xp DESC),
    u.weekly_xp
  FROM public.users u
  WHERE u.weekly_xp >= 1
  ON CONFLICT (user_id, week_start_date) DO NOTHING;

  UPDATE public.users SET weekly_xp = 0;

  UPDATE app_settings
     SET value = to_jsonb(v_today::text)
   WHERE key = 'weekly_reset_last';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.archive_and_reset_weekly_xp() FROM PUBLIC, anon, authenticated;

-- Tighten cron: once at 08:00 UTC Monday instead of every 2 min
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'archive-and-reset-weekly-xp';

SELECT cron.schedule(
  'archive-and-reset-weekly-xp',
  '0 8 * * 1',
  $$SELECT public.archive_and_reset_weekly_xp()$$
);
