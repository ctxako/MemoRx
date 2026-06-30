-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- The apple_user_id column was dropped at some point during schema evolution.
-- iOS UserRow + upsertUser both reference it; the latter has been silently
-- failing every Apple sign-in because the column was missing. Restore it
-- (nullable text). Will also be used by the upcoming Sign in with Apple flow
-- to look up legacy rows when migrating anon users to Apple-linked identities.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS apple_user_id text;
CREATE INDEX IF NOT EXISTS users_apple_user_id_idx ON public.users (apple_user_id) WHERE apple_user_id IS NOT NULL;
