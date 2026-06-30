-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Fix cooldown bypass: clients must not be able to PATCH display_name_updated_at directly.
-- The stamp_display_name_updated_at trigger (SECURITY DEFINER) auto-writes this column
-- on every display_name change, so revoking client write access doesn't break anything.
revoke update (display_name_updated_at) on public.users from authenticated;
