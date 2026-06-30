-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

ALTER TABLE public.daily_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.banned_usernames ENABLE ROW LEVEL SECURITY;
