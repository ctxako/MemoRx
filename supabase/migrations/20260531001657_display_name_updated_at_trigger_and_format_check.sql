-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Auto-stamp display_name_updated_at whenever the name actually changes
CREATE OR REPLACE FUNCTION set_display_name_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.display_name IS DISTINCT FROM OLD.display_name THEN
    NEW.display_name_updated_at = now();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_display_name_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION set_display_name_updated_at();

-- Format: 2-20 chars, letters/numbers/spaces, no consecutive spaces, alphanumeric start+end
ALTER TABLE public.users
ADD CONSTRAINT users_display_name_format CHECK (
  display_name IS NULL OR (
    char_length(display_name) BETWEEN 2 AND 20
    AND display_name ~ '^[A-Za-z0-9][A-Za-z0-9 ]*[A-Za-z0-9]$'
    AND display_name !~ '  '
  )
);
