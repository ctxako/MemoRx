-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- (1) Recreate the public leaderboard view.
--     Expose the caller's REAL id only on their own row (needed for self-highlight in the
--     client); every other row gets a stable, non-reversible uuid surrogate so raw auth
--     UUIDs can no longer be harvested from the leaderboard and fed to claim_apple_user-
--     style functions. Column stays uuid, so existing SELECT grants are preserved.
CREATE OR REPLACE VIEW public.leaderboard_public
WITH (security_invoker = false) AS
SELECT
  CASE WHEN u.id = auth.uid() THEN u.id
       ELSE md5(u.id::text || 'memorx-lb-v1')::uuid
  END AS id,
  u.legacy_user_id,
  u.display_name,
  u.total_xp,
  u.weekly_xp,
  u.streak,
  u.level_title,
  u.drugs_studied,
  u.student_level
FROM public.users u
WHERE lower(btrim(u.display_name::text)) !~~ '%signed out%'::text;

-- (2) CRITICAL: this view is SECURITY DEFINER (executes as postgres, bypassing RLS) and was
--     auto-updatable with INSERT/UPDATE/DELETE granted to anon + authenticated. That let an
--     unauthenticated caller rewrite ANY user's row (XP, streak, display_name) through the
--     view. Strip all write privileges; the leaderboard is read-only.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.leaderboard_public FROM anon, authenticated, PUBLIC;
