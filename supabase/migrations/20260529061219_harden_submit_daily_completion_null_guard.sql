-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

CREATE OR REPLACE FUNCTION public.submit_daily_completion(p_user_id uuid, p_drug_id text, p_correct_count integer, p_total_questions integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_challenge       daily_challenges%ROWTYPE;
  v_daily_xp        integer;
  v_milestone_bonus integer := 0;
  v_milestone_day   integer;
  v_milestone_hits  jsonb := '[]'::jsonb;
  v_streak          integer;
  v_rows            integer;
  v_today           date;
  v_milestones      CONSTANT integer[][] := ARRAY[ARRAY[7,50], ARRAY[14,100], ARRAY[30,250], ARRAY[90,600]];
  v_i               integer;
  v_m_day           integer;
  v_m_xp            integer;
BEGIN
  PERFORM maybe_reset_weekly_xp();

  IF auth.uid() IS NULL OR p_user_id <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_mismatch');
  END IF;

  v_today := current_challenge_date();
  SELECT * INTO v_challenge FROM daily_challenges WHERE challenge_date = v_today;

  IF NOT FOUND OR v_challenge.drug_id <> p_drug_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'drug_not_todays_challenge',
      'challenge_date', v_today,
      'expected_drug_id', COALESCE(v_challenge.drug_id, '')
    );
  END IF;

  IF p_total_questions <= 0 THEN
    v_daily_xp := 0;
  ELSE
    v_daily_xp := ROUND(50.0 * p_correct_count / p_total_questions);
  END IF;

  INSERT INTO daily_completions (user_id, challenge_date, xp_awarded, correct_count, total_questions)
  VALUES (p_user_id, v_today, v_daily_xp, p_correct_count, p_total_questions)
  ON CONFLICT (user_id, challenge_date) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    v_streak := compute_user_streak(p_user_id);
    RETURN jsonb_build_object(
      'success', false,
      'error', 'already_completed',
      'challenge_date', v_today,
      'streak', v_streak
    );
  END IF;

  v_streak := compute_user_streak(p_user_id);

  FOR v_i IN 1..array_length(v_milestones, 1) LOOP
    v_m_day := v_milestones[v_i][1];
    v_m_xp  := v_milestones[v_i][2];
    IF v_streak >= v_m_day THEN
      INSERT INTO user_milestone_claims (user_id, milestone_day, xp_awarded)
      VALUES (p_user_id, v_m_day, v_m_xp)
      ON CONFLICT (user_id, milestone_day) DO NOTHING;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows = 1 THEN
        v_milestone_bonus := v_milestone_bonus + v_m_xp;
        v_milestone_day := v_m_day;
        v_milestone_hits := v_milestone_hits || jsonb_build_object('day', v_m_day, 'xp', v_m_xp);
      END IF;
    END IF;
  END LOOP;

  UPDATE users
     SET total_xp  = total_xp  + v_daily_xp + v_milestone_bonus,
         weekly_xp = weekly_xp + v_daily_xp + v_milestone_bonus,
         streak    = v_streak
   WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'xp_awarded', v_daily_xp + v_milestone_bonus,
    'daily_xp', v_daily_xp,
    'milestone_bonus', v_milestone_bonus,
    'milestone_day', v_milestone_day,
    'milestones', v_milestone_hits,
    'streak', v_streak,
    'challenge_date', v_today
  );
END;
$function$
