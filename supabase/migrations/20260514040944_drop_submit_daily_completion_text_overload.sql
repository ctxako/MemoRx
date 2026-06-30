-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- The (text, text, int, int) overload was left over from when users.id was text.
-- It contains a fragile `lower(id)` against the now-uuid users.id column that
-- would error at runtime. The (uuid, text, int, int) overload is the safe one;
-- PostgREST routes JSON string p_user_id values to it via uuid parsing.
DROP FUNCTION IF EXISTS public.submit_daily_completion(text, text, integer, integer);
