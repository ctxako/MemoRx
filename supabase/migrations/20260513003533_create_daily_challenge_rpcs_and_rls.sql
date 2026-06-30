-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- RLS
-- ============================================================

-- daily_challenges: public read, service_role write (bypasses RLS by default)
ALTER TABLE daily_challenges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "daily_challenges_read_anon"
  ON daily_challenges FOR SELECT TO anon USING (true);
CREATE POLICY "daily_challenges_read_authenticated"
  ON daily_challenges FOR SELECT TO authenticated USING (true);

-- daily_completions: user reads own; writes only via SECURITY DEFINER RPC
ALTER TABLE daily_completions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "daily_completions_read_own"
  ON daily_completions FOR SELECT TO authenticated
  USING (auth.uid()::text = user_id);

-- admin_audit_log: no public access (service_role bypasses RLS)
ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

-- app_settings: no public access (accessed only via SECURITY DEFINER functions)
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- maybe_reset_weekly_xp() — idempotent weekly reset helper
-- ============================================================
CREATE OR REPLACE FUNCTION maybe_reset_weekly_xp()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_last_reset date;
  v_today      date;
BEGIN
  v_today := current_challenge_date();

  SELECT (value #>> '{}')::date INTO v_last_reset
  FROM app_settings WHERE key = 'weekly_reset_last';

  -- DOW 1 = Monday; only reset once per week
  IF EXTRACT(DOW FROM v_today) = 1 AND v_today > v_last_reset THEN
    UPDATE users SET weekly_xp = 0;
    UPDATE app_settings
       SET value = to_jsonb(v_today::text)
     WHERE key = 'weekly_reset_last';
  END IF;
END;
$$;

-- ============================================================
-- get_current_challenge() — returns today's challenge or null
-- ============================================================
CREATE OR REPLACE FUNCTION get_current_challenge()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT to_jsonb(dc)
  FROM (
    SELECT challenge_date, drug_id, title, difficulty, xp_base
    FROM daily_challenges
    WHERE challenge_date = current_challenge_date()
    LIMIT 1
  ) dc;
$$;

-- ============================================================
-- submit_daily_completion()
-- ============================================================
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
  -- Weekly reset (idempotent — no-op if already reset this week)
  PERFORM maybe_reset_weekly_xp();

  -- Caller must match the user they're submitting for
  IF p_user_id <> auth.uid()::text THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_mismatch');
  END IF;

  -- Load today's challenge
  v_today := current_challenge_date();
  SELECT * INTO v_challenge
  FROM daily_challenges WHERE challenge_date = v_today;

  -- Drug must match today's challenge
  IF NOT FOUND OR v_challenge.drug_id <> p_drug_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'drug_not_todays_challenge');
  END IF;

  -- Compute XP
  IF p_total_questions <= 0 THEN
    v_xp_awarded := 0;
  ELSE
    v_xp_awarded := ROUND(v_challenge.xp_base::numeric * p_correct_count / p_total_questions);
  END IF;

  -- Insert; silently skip if already completed
  INSERT INTO daily_completions (user_id, challenge_date, xp_awarded, correct_count, total_questions)
  VALUES (p_user_id, v_today, v_xp_awarded, p_correct_count, p_total_questions)
  ON CONFLICT (user_id, challenge_date) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_completed', 'challenge_date', v_today);
  END IF;

  -- Award XP (leaderboard_public is a view on users — no separate update needed)
  UPDATE users
     SET total_xp  = total_xp  + v_xp_awarded,
         weekly_xp = weekly_xp + v_xp_awarded
   WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true, 'xp_awarded', v_xp_awarded, 'challenge_date', v_today);
END;
$$;

-- ============================================================
-- admin_adjust_user_xp() — separate total/weekly deltas
-- ============================================================
CREATE OR REPLACE FUNCTION admin_adjust_user_xp(
  p_admin_id        text,
  p_user_id         text,
  p_total_xp_delta  integer DEFAULT 0,
  p_weekly_xp_delta integer DEFAULT 0,
  p_reason          text    DEFAULT NULL,
  p_ticket_id       text    DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_before jsonb;
  v_after  jsonb;
BEGIN
  SELECT to_jsonb(u) INTO v_before FROM users u WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'user_not_found');
  END IF;

  UPDATE users
     SET total_xp  = total_xp  + p_total_xp_delta,
         weekly_xp = weekly_xp + p_weekly_xp_delta
   WHERE id = p_user_id;

  SELECT to_jsonb(u) INTO v_after FROM users u WHERE id = p_user_id;

  INSERT INTO admin_audit_log
    (admin_id, action, entity_type, entity_id, reason, ticket_id, before_data, after_data)
  VALUES
    (p_admin_id, 'adjust_xp', 'user', p_user_id, p_reason, p_ticket_id, v_before, v_after);

  RETURN jsonb_build_object(
    'success', true,
    'total_xp_delta', p_total_xp_delta,
    'weekly_xp_delta', p_weekly_xp_delta
  );
END;
$$;
