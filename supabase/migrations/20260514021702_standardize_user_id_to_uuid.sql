-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- Standardize users.id and daily_completions.user_id to uuid
-- ============================================================

BEGIN;

-- ── 1. Drop leaderboard_public view (depends on users.id)
DROP VIEW IF EXISTS public.leaderboard_public;

-- ── 2. Drop FK from daily_completions → users
ALTER TABLE public.daily_completions
  DROP CONSTRAINT IF EXISTS daily_completions_user_id_fkey;

-- ── 3. Drop all RLS policies on users that cast to text
DROP POLICY IF EXISTS "users_read_own"   ON public.users;
DROP POLICY IF EXISTS "users_insert_own" ON public.users;
DROP POLICY IF EXISTS "users_update_own" ON public.users;
DROP POLICY IF EXISTS "users_delete_own" ON public.users;

-- ── 4. Drop RLS policies on daily_completions that cast to text
DROP POLICY IF EXISTS "daily_completions_read_own"   ON public.daily_completions;
DROP POLICY IF EXISTS "daily_completions_insert_own" ON public.daily_completions;

-- ── 5. Convert users.id text → uuid
ALTER TABLE public.users
  ALTER COLUMN id TYPE uuid USING id::uuid;

-- ── 6. Convert daily_completions.user_id text → uuid
ALTER TABLE public.daily_completions
  ALTER COLUMN user_id TYPE uuid USING user_id::uuid;

-- ── 7. Re-add FK from daily_completions → users
ALTER TABLE public.daily_completions
  ADD CONSTRAINT daily_completions_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id);

-- ── 8. Recreate leaderboard_public — now id is uuid type
--    SELECT only for anon and authenticated (fix #2 already applied,
--    recreating here maintains that posture)
CREATE VIEW public.leaderboard_public
WITH (security_invoker = false)
AS
  SELECT
    id,
    legacy_user_id,
    display_name,
    total_xp,
    weekly_xp,
    streak,
    level_title,
    drugs_studied
  FROM public.users
  WHERE lower(btrim((display_name)::text)) NOT LIKE '%signed out%';

GRANT SELECT ON public.leaderboard_public TO anon, authenticated;

-- ── 9. Recreate users RLS policies — clean uuid, no text cast
CREATE POLICY "users_read_own"
  ON public.users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "users_insert_own"
  ON public.users FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "users_update_own"
  ON public.users FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "users_delete_own"
  ON public.users FOR DELETE
  USING (auth.uid() = id);

-- ── 10. Recreate daily_completions RLS policies — clean uuid
CREATE POLICY "daily_completions_read_own"
  ON public.daily_completions FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "daily_completions_insert_own"
  ON public.daily_completions FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- ── 11. Update submit_daily_completion — now accepts uuid natively
CREATE OR REPLACE FUNCTION public.submit_daily_completion(
  p_user_id uuid,
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

  IF p_user_id <> auth.uid() THEN
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
  VALUES (p_user_id, v_today, v_xp_awarded, p_correct_count, p_total_questions)
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
   WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'xp_awarded', v_xp_awarded,
    'challenge_date', v_today
  );
END;
$$;

-- ── 12. Update admin_adjust_user_xp — accept uuid natively
CREATE OR REPLACE FUNCTION public.admin_adjust_user_xp(
  p_admin_id text,
  p_user_id uuid,
  p_total_xp_delta integer DEFAULT 0,
  p_weekly_xp_delta integer DEFAULT 0,
  p_reason text DEFAULT NULL,
  p_ticket_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    (p_admin_id, 'adjust_xp', 'user', p_user_id::text, p_reason, p_ticket_id, v_before, v_after);

  RETURN jsonb_build_object(
    'success', true,
    'total_xp_delta', p_total_xp_delta,
    'weekly_xp_delta', p_weekly_xp_delta
  );
END;
$$;

COMMIT;
