-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- STEP 1: Replace users policies — own row only (id is text)
-- ============================================================
DROP POLICY IF EXISTS "anon_read_all_users" ON public.users;
DROP POLICY IF EXISTS "authenticated_read_all_users" ON public.users;

DROP POLICY IF EXISTS "users_read_own" ON public.users;
CREATE POLICY "users_read_own" ON public.users
  FOR SELECT
  USING ((auth.uid())::text = id);

DROP POLICY IF EXISTS "users_insert_own" ON public.users;
CREATE POLICY "users_insert_own" ON public.users
  FOR INSERT
  WITH CHECK ((auth.uid())::text = id);

DROP POLICY IF EXISTS "users_update_own" ON public.users;
CREATE POLICY "users_update_own" ON public.users
  FOR UPDATE
  USING ((auth.uid())::text = id)
  WITH CHECK ((auth.uid())::text = id);

DROP POLICY IF EXISTS "users_delete_own" ON public.users;
CREATE POLICY "users_delete_own" ON public.users
  FOR DELETE
  USING ((auth.uid())::text = id);

-- ============================================================
-- STEP 2: Recreate leaderboard_public with security_invoker=false
-- ============================================================
CREATE OR REPLACE VIEW public.leaderboard_public
WITH (security_invoker = false) AS
SELECT
  id,
  legacy_user_id,
  display_name,
  total_xp,
  weekly_xp,
  streak,
  level_title,
  drugs_studied
FROM public.users
WHERE lower(btrim(display_name)) NOT LIKE '%signed out%';

GRANT SELECT ON public.leaderboard_public TO authenticated;
