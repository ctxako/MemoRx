-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Atomically zeros all user progress and deletes all study/quiz history.
-- Runs as SECURITY DEFINER so it can delete from tables the user doesn't
-- have a DELETE RLS policy on (daily_completions, user_milestone_claims).
-- The caller must be the owner of the account (auth.uid() must match p_user_id).
CREATE OR REPLACE FUNCTION public.reset_user_progress(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR v_uid <> p_user_id THEN
    RAISE EXCEPTION 'unauthorized: can only reset your own account';
  END IF;

  -- Zero XP, streak, and level on the users row.
  -- Preserve identity columns: apple_user_id, display_name, is_lifetime,
  -- legacy_user_id, naplex_date, student_level, start_date, created_at.
  UPDATE public.users
  SET total_xp      = 0,
      weekly_xp     = 0,
      streak        = 0,
      drugs_studied = 0,
      level         = 1,
      level_title   = NULL,
      last_active   = now()
  WHERE id = p_user_id;

  -- Wipe all study data.
  DELETE FROM public.drug_progress        WHERE user_id = p_user_id;
  DELETE FROM public.quiz_attempts        WHERE user_id = p_user_id;
  DELETE FROM public.daily_completions    WHERE user_id = p_user_id;
  DELETE FROM public.user_milestone_claims WHERE user_id = p_user_id;
END;
$$;

-- Grant execute to authenticated users (they still hit the auth.uid() check above).
GRANT EXECUTE ON FUNCTION public.reset_user_progress(uuid) TO authenticated;
