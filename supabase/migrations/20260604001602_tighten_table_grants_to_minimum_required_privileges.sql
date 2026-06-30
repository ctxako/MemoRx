-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Read-only content tables
REVOKE ALL ON public.drugs FROM anon, authenticated;
GRANT SELECT ON public.drugs TO anon, authenticated;

REVOKE ALL ON public.daily_challenges FROM anon, authenticated;
GRANT SELECT ON public.daily_challenges TO anon, authenticated;

REVOKE ALL ON public.class_quizzes FROM anon, authenticated;
GRANT SELECT ON public.class_quizzes TO anon, authenticated;

REVOKE ALL ON public.banned_usernames FROM anon, authenticated;
GRANT SELECT ON public.banned_usernames TO anon, authenticated;

-- Admin-only tables (RLS already blocks, but remove unnecessary grants)
REVOKE ALL ON public.admin_audit_log FROM anon, authenticated;
REVOKE ALL ON public.app_settings FROM anon, authenticated;

-- User data tables: revoke from anon, grant only what authenticated needs
REVOKE ALL ON public.weekly_results FROM anon, authenticated;
GRANT SELECT ON public.weekly_results TO authenticated;

REVOKE ALL ON public.user_milestone_claims FROM anon, authenticated;
GRANT SELECT ON public.user_milestone_claims TO authenticated;

REVOKE ALL ON public.daily_completions FROM anon, authenticated;
GRANT SELECT ON public.daily_completions TO authenticated;

REVOKE ALL ON public.drug_progress FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.drug_progress TO authenticated;

REVOKE ALL ON public.quiz_attempts FROM anon, authenticated;
GRANT SELECT, INSERT ON public.quiz_attempts TO authenticated;

REVOKE ALL ON public.drug_submissions FROM anon, authenticated;
GRANT INSERT ON public.drug_submissions TO authenticated;

-- username_reports: clean up anon
REVOKE ALL ON public.username_reports FROM anon;

-- users table: column-restricted UPDATE already exists, just revoke excess
REVOKE TRUNCATE, REFERENCES, TRIGGER ON public.users FROM anon, authenticated;
