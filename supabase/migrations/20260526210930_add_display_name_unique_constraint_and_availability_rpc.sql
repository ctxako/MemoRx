-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Unique index on display_name (citext handles case-insensitivity, NULLs are excluded automatically)
CREATE UNIQUE INDEX IF NOT EXISTS users_display_name_unique
ON public.users (display_name);

-- RPC for client to check availability before submitting
CREATE OR REPLACE FUNCTION is_display_name_available(p_name citext)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.users WHERE display_name = p_name
  );
$$;
