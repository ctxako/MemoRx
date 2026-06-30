-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- banned_usernames: add anon read
-- Anonymous users need to check banned terms during onboarding
-- before they have a signed-in session.
-- ============================================================
CREATE POLICY "banned_usernames_read_anon"
ON public.banned_usernames
FOR SELECT
TO anon
USING (true);

-- ============================================================
-- class_quizzes: add anon read
-- Anonymous users need to load class quiz content.
-- Write access remains denied for all client roles.
-- ============================================================
CREATE POLICY "class_quizzes_read_anon"
ON public.class_quizzes
FOR SELECT
TO anon
USING (true);
