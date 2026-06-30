-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_display_name_unique;
