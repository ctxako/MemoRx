-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Whenever a new auth.users row is created (anonymous OR Apple-linked),
-- immediately insert a minimal public.users stub so FK constraints never fail.
-- claim_apple_user already uses ON CONFLICT DO UPDATE and will upgrade the stub.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, is_anonymous, created_at, last_active)
  VALUES (NEW.id, true, now(), now())
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_auth_user();

-- Backfill: create stub rows for the existing orphan auth users
-- (anonymous sessions that never got a public.users row).
INSERT INTO public.users (id, is_anonymous, created_at, last_active)
SELECT id, true, created_at, now()
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.users)
ON CONFLICT (id) DO NOTHING;
