-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- submit_daily_completion's guard `p_user_id <> auth.uid()` evaluates to NULL
-- (not TRUE) for the unauthenticated anon role, bypassing the self-only check.
-- Combined with the anon EXECUTE grant and SECURITY DEFINER, this let anyone
-- using the public anon key award/complete the daily challenge for an arbitrary
-- user UUID (UUIDs are exposed via leaderboard_public.id).
-- Real users authenticate (even anonymous sign-in -> authenticated role with a
-- non-null auth.uid()), so revoking the anon grant does not affect the app flow.
REVOKE EXECUTE ON FUNCTION
  public.submit_daily_completion(uuid, text, integer, integer)
FROM anon;
