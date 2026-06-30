-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


ALTER TABLE daily_challenges
  DROP COLUMN IF EXISTS title,
  DROP COLUMN IF EXISTS difficulty,
  DROP COLUMN IF EXISTS notes,
  DROP COLUMN IF EXISTS xp_base;

-- get_current_challenge: return xp_base as hardcoded 50 so iOS clients don't break
CREATE OR REPLACE FUNCTION get_current_challenge()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$
  WITH et AS (
    SELECT NOW() AT TIME ZONE 'America/New_York' AS now_et
  ),
  clock AS (
    SELECT
      current_challenge_date()                              AS today,
      EXTRACT(HOUR   FROM now_et)::int                     AS et_hour,
      EXTRACT(MINUTE FROM now_et)::int                     AS et_minute,
      CASE
        WHEN EXTRACT(HOUR FROM now_et) < 4
          THEN CEIL(EXTRACT(EPOCH FROM (
            date_trunc('day', now_et) + INTERVAL '4 hours' - now_et
          )) / 60)::int
        ELSE CEIL(EXTRACT(EPOCH FROM (
          date_trunc('day', now_et) + INTERVAL '1 day 4 hours' - now_et
        )) / 60)::int
      END AS minutes_until
    FROM et
  ),
  ch AS (
    SELECT drug_id
    FROM daily_challenges
    WHERE challenge_date = current_challenge_date()
    LIMIT 1
  )
  SELECT jsonb_build_object(
    'current_challenge_date',         clock.today,
    'minutes_until_next_et_boundary', clock.minutes_until,
    'server_et_hour',                 clock.et_hour,
    'server_et_minute',               clock.et_minute,
    'drug_id',                        ch.drug_id,
    'xp_base',                        50
  )
  FROM clock
  LEFT JOIN ch ON true;
$$;

-- submit_daily_completion: use hardcoded 50 instead of xp_base column
CREATE OR REPLACE FUNCTION submit_daily_completion(
  p_user_id         text,
  p_drug_id         text,
  p_correct_count   integer,
  p_total_questions integer
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_challenge   daily_challenges%ROWTYPE;
  v_xp_awarded  integer;
  v_rows        integer;
  v_today       date;
BEGIN
  PERFORM maybe_reset_weekly_xp();

  IF p_user_id <> auth.uid()::text THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_mismatch');
  END IF;

  v_today := current_challenge_date();
  SELECT * INTO v_challenge FROM daily_challenges WHERE challenge_date = v_today;

  IF NOT FOUND OR v_challenge.drug_id <> p_drug_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'drug_not_todays_challenge');
  END IF;

  IF p_total_questions <= 0 THEN
    v_xp_awarded := 0;
  ELSE
    v_xp_awarded := ROUND(50.0 * p_correct_count / p_total_questions);
  END IF;

  INSERT INTO daily_completions (user_id, challenge_date, xp_awarded, correct_count, total_questions)
  VALUES (p_user_id, v_today, v_xp_awarded, p_correct_count, p_total_questions)
  ON CONFLICT (user_id, challenge_date) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_completed', 'challenge_date', v_today);
  END IF;

  UPDATE users
     SET total_xp  = total_xp  + v_xp_awarded,
         weekly_xp = weekly_xp + v_xp_awarded
   WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true, 'xp_awarded', v_xp_awarded, 'challenge_date', v_today);
END;
$$;
