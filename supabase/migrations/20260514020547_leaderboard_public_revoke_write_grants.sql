-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- leaderboard_public: revoke all write privileges
-- This view should be strictly read-only for all client roles.
-- The backing users table has RLS; this removes the extra
-- attack surface on the view itself.
-- ============================================================

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON public.leaderboard_public
FROM anon, authenticated;

-- Explicitly confirm SELECT remains — belt and suspenders
GRANT SELECT ON public.leaderboard_public TO anon, authenticated;
