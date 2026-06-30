-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- maybe_reset_weekly_xp zeroes everyone's weekly_xp on Mondays with no
-- leaderboard snapshot; it must not be client-callable. It is only invoked
-- internally by submit_daily_completion (SECURITY DEFINER, runs as postgres),
-- so revoking the PUBLIC grant does not affect the daily-completion flow.
REVOKE EXECUTE ON FUNCTION public.maybe_reset_weekly_xp() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.maybe_reset_weekly_xp() TO service_role;
