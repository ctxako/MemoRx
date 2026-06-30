-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- 1. Enable citext
CREATE EXTENSION IF NOT EXISTS citext;

-- 2. Drop dependent view temporarily
DROP VIEW IF EXISTS public.leaderboard_public;

-- 3. Convert display_name to citext
ALTER TABLE public.users
  ALTER COLUMN display_name TYPE citext USING display_name::citext;

-- 4. Add unique constraint
ALTER TABLE public.users
  ADD CONSTRAINT users_display_name_unique UNIQUE (display_name);

-- 5. Recreate leaderboard_public view (display_name now citext, filter still works)
CREATE VIEW public.leaderboard_public AS
  SELECT id, legacy_user_id, display_name, total_xp, weekly_xp, streak, level_title, drugs_studied
  FROM public.users
  WHERE lower(btrim(display_name::text)) NOT LIKE '%signed out%';

-- 6. Add cooldown + student level columns
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS display_name_updated_at timestamp without time zone,
  ADD COLUMN IF NOT EXISTS student_level text,
  ADD COLUMN IF NOT EXISTS student_level_title text;

-- 7. Create banned_usernames table
CREATE TABLE IF NOT EXISTS public.banned_usernames (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  term citext NOT NULL UNIQUE,
  created_at timestamp without time zone DEFAULT now()
);

-- 8. Seed starter banned list
INSERT INTO public.banned_usernames (term) VALUES
  ('admin'), ('moderator'), ('memorx'), ('support'), ('official'),
  ('fuck'), ('shit'), ('ass'), ('bitch'), ('cunt'),
  ('nigger'), ('nigga'), ('faggot'), ('retard'), ('whore'),
  ('nazi'), ('hitler'), ('rape'), ('rapist'), ('terrorist')
ON CONFLICT DO NOTHING;

-- 9. RLS on banned_usernames
ALTER TABLE public.banned_usernames ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read banned_usernames"
  ON public.banned_usernames
  FOR SELECT
  TO authenticated
  USING (true);
