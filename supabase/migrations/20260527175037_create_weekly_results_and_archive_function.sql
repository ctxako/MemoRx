-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- 1. Snapshot table
CREATE TABLE public.weekly_results (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  week_start_date date NOT NULL,
  rank int NOT NULL,
  xp int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, week_start_date)
);

CREATE INDEX idx_weekly_results_user
  ON public.weekly_results(user_id, week_start_date DESC);

ALTER TABLE public.weekly_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users read own weekly_results"
  ON public.weekly_results
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- 2. Atomic archive + reset function
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
    FROM app_settings WHERE key = 'weekly_reset_last';

  -- Only fire on Mondays, only once per Monday
  IF EXTRACT(DOW FROM v_today) <> 1 OR v_today <= v_last_reset THEN
    RETURN;
  END IF;

  v_week_start := v_today - 7;  -- the Monday that started the week being archived

  -- Insert snapshot rows for everyone with XP > 0 who is visible on the leaderboard
  INSERT INTO public.weekly_results (user_id, week_start_date, rank, xp)
  SELECT
    u.id,
    v_week_start,
    RANK() OVER (ORDER BY u.weekly_xp DESC),
    u.weekly_xp
  FROM public.users u
  WHERE u.weekly_xp >= 1
    AND u.id IN (SELECT lp.id FROM public.leaderboard_public lp)
  ON CONFLICT (user_id, week_start_date) DO NOTHING;

  -- Then zero out
  UPDATE public.users SET weekly_xp = 0;

  -- Bump the guard so subsequent ticks today no-op
  UPDATE app_settings
     SET value = to_jsonb(v_today::text)
   WHERE key = 'weekly_reset_last';
END;
$$;
