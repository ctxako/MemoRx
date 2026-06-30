-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- daily_completions: immutable append-only RLS
-- ============================================================
-- SELECT: own rows only (already exists, recreating for clarity)
DROP POLICY IF EXISTS "daily_completions_read_own" ON public.daily_completions;

CREATE POLICY "daily_completions_read_own"
ON public.daily_completions
FOR SELECT
TO authenticated
USING ((auth.uid())::text = user_id);

-- INSERT: authenticated users may only insert their own rows
-- No UPDATE or DELETE policies — completions are immutable from the client
CREATE POLICY "daily_completions_insert_own"
ON public.daily_completions
FOR INSERT
TO authenticated
WITH CHECK ((auth.uid())::text = user_id);

-- ============================================================
-- submit_daily_completion: harden user_id comparison
-- lowercase both sides so Swift UUID strings never mismatch
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_daily_completion(
  p_user_id text,
  p_drug_id text,
  p_correct_count integer,
  p_total_questions integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_challenge   daily_challenges%ROWTYPE;
  v_xp_awarded  integer;
  v_rows        integer;
  v_today       date;
BEGIN
  PERFORM maybe_reset_weekly_xp();

  -- Case-insensitive comparison — Swift sends lowercase UUIDs,
  -- Postgres auth.uid()::text may vary by environment
  IF lower(p_user_id) <> lower(auth.uid()::text) THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_mismatch');
  END IF;

  v_today := current_challenge_date();
  SELECT * INTO v_challenge FROM daily_challenges WHERE challenge_date = v_today;

  IF NOT FOUND OR v_challenge.drug_id <> p_drug_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'drug_not_todays_challenge',
      'challenge_date', v_today,
      'expected_drug_id', v_challenge.drug_id
    );
  END IF;

  IF p_total_questions <= 0 THEN
    v_xp_awarded := 0;
  ELSE
    v_xp_awarded := ROUND(50.0 * p_correct_count / p_total_questions);
  END IF;

  INSERT INTO daily_completions (user_id, challenge_date, xp_awarded, correct_count, total_questions)
  VALUES (lower(p_user_id), v_today, v_xp_awarded, p_correct_count, p_total_questions)
  ON CONFLICT (user_id, challenge_date) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'already_completed',
      'challenge_date', v_today
    );
  END IF;

  UPDATE users
     SET total_xp  = total_xp  + v_xp_awarded,
         weekly_xp = weekly_xp + v_xp_awarded
   WHERE lower(id) = lower(p_user_id);

  RETURN jsonb_build_object(
    'success', true,
    'xp_awarded', v_xp_awarded,
    'challenge_date', v_today
  );
END;
$$;
