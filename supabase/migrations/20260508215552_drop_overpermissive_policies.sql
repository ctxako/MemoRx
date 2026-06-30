-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Drop overpermissive policies on drug_progress
DROP POLICY IF EXISTS "allow all on drug_progress" ON public.drug_progress;
DROP POLICY IF EXISTS "allow anon read" ON public.drug_progress;

-- Drop overpermissive policies on drug_submissions
DROP POLICY IF EXISTS "allow all on drug_submissions" ON public.drug_submissions;
DROP POLICY IF EXISTS "allow anon read" ON public.drug_submissions;
