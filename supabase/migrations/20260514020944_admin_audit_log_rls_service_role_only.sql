-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- admin_audit_log: service role only access
-- RLS was enabled with zero policies = total lockout for all
-- roles including authenticated admins. Service role bypasses
-- RLS natively in Postgres, but we add an explicit policy for
-- clarity and to document intent. All reads/writes from the
-- admin proxy (service role) work as expected. No client role
-- (anon or authenticated) can touch this table directly.
-- ============================================================

CREATE POLICY "admin_audit_log_service_role_only"
ON public.admin_audit_log
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
