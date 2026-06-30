-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


CREATE OR REPLACE FUNCTION delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Delete app data first (FK order)
  DELETE FROM public.daily_completions WHERE user_id = v_user_id;
  DELETE FROM public.quiz_attempts WHERE user_id = v_user_id;
  DELETE FROM public.user_milestone_claims WHERE user_id = v_user_id;
  DELETE FROM public.users WHERE id = v_user_id;

  -- Delete auth user (cascades auth schema tables automatically)
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- Only the authenticated user can call this (no anon access)
REVOKE ALL ON FUNCTION delete_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION delete_my_account() TO authenticated;
