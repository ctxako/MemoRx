-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

ALTER TABLE drug_progress
  ADD COLUMN IF NOT EXISTS ease_factor FLOAT,
  ADD COLUMN IF NOT EXISTS repetition_number INTEGER,
  ADD COLUMN IF NOT EXISTS interval_days INTEGER;
