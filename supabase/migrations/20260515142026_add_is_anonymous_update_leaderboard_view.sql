-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- 1. Add is_anonymous flag to users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT false;

-- 2. Backfill: rows with no apple_user_id and no meaningful progress are likely guests.
--    Only mark rows that have never had a real identity set.
UPDATE public.users
SET is_anonymous = true
WHERE apple_user_id IS NULL
  AND total_xp = 0
  AND streak   = 0
  AND (display_name IS NULL OR lower(btrim(display_name::text)) IN ('', 'unknown', 'anonymous', 'player', 'guest'));

-- 3. When claim_apple_user links an Apple ID, clear the anonymous flag.
--    (The RPC itself is updated in the next migration.)

-- 4. Rebuild leaderboard_public view: only show Apple-authenticated, non-anonymous users
--    with a real display name.
CREATE OR REPLACE VIEW public.leaderboard_public AS
  SELECT id,
         legacy_user_id,
         display_name,
         total_xp,
         weekly_xp,
         streak,
         level_title,
         drugs_studied
  FROM   public.users
  WHERE  apple_user_id IS NOT NULL
    AND  is_anonymous  = false
    AND  display_name  IS NOT NULL
    AND  lower(btrim(display_name::text)) !~~ '%signed out%'
    AND  btrim(display_name::text) <> '';
