-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- app_settings: internal/service role only
-- Both rows are server-internal state used exclusively by
-- SECURITY DEFINER RPCs (maybe_reset_weekly_xp,
-- auto_fill_challenge_schedule, admin_reset_cycle).
-- Exposing challenge_cycle_remaining to clients would leak
-- upcoming drug rotation. No client role should read or
-- write this table directly.
-- SECURITY DEFINER functions bypass RLS, so all RPCs
-- continue to work without any client-facing policy.
-- ============================================================

CREATE POLICY "app_settings_service_role_only"
ON public.app_settings
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
