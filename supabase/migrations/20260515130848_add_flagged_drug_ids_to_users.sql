-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS flagged_drug_ids jsonb DEFAULT '[]'::jsonb;
