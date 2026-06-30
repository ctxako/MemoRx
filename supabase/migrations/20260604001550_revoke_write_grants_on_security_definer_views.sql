-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.class_quiz_content FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.class_quiz_guides FROM anon, authenticated;
