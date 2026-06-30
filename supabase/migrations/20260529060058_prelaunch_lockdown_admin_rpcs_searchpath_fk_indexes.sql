-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- 1. Lock down admin / maintenance RPCs: remove the default PUBLIC execute
--    grant so anon/authenticated can no longer call them via PostgREST.
--    Cron jobs run as the postgres superuser and are unaffected.
REVOKE EXECUTE ON FUNCTION
  public.admin_adjust_user_xp(text, text, integer, integer, text, text),
  public.admin_adjust_user_xp(text, uuid, integer, integer, text, text),
  public.admin_reset_cycle(),
  public.fill_challenge_buffer(integer),
  public.archive_and_reset_weekly_xp(),
  public.claim_challenge_drug(date, text),
  public.reset_user_progress(uuid)
FROM PUBLIC, anon, authenticated;

-- Preserve a backend path for the genuine admin/maintenance operations.
GRANT EXECUTE ON FUNCTION
  public.admin_adjust_user_xp(text, text, integer, integer, text, text),
  public.admin_adjust_user_xp(text, uuid, integer, integer, text, text),
  public.admin_reset_cycle(),
  public.fill_challenge_buffer(integer),
  public.archive_and_reset_weekly_xp(),
  public.claim_challenge_drug(date, text)
TO service_role;

-- 2. Pin search_path on SECURITY DEFINER / helper functions that lacked it.
--    'public' matches the existing convention and keeps citext operators
--    (used by is_display_name_available) resolvable.
ALTER FUNCTION public.admin_adjust_user_xp(text, text, integer, integer, text, text) SET search_path = public;
ALTER FUNCTION public.delete_my_account() SET search_path = public;
ALTER FUNCTION public.maybe_reset_weekly_xp() SET search_path = public;
ALTER FUNCTION public.is_display_name_available(citext) SET search_path = public;
ALTER FUNCTION public.check_challenge_locked() SET search_path = public;
ALTER FUNCTION public.current_challenge_date() SET search_path = public;

-- 3. Add missing foreign-key indexes.
CREATE INDEX IF NOT EXISTS idx_daily_challenges_drug_id ON public.daily_challenges (drug_id);
CREATE INDEX IF NOT EXISTS idx_daily_completions_challenge_date ON public.daily_completions (challenge_date);
CREATE INDEX IF NOT EXISTS idx_quiz_attempts_user_id ON public.quiz_attempts (user_id);
