-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Functions that leak private data to unauthenticated callers
REVOKE EXECUTE ON FUNCTION public.is_user_subscribed(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.compute_user_streak(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_cycle_status() FROM anon;

-- Trigger/event-trigger functions exposed as RPC unnecessarily
REVOKE EXECUTE ON FUNCTION public.append_new_drug_to_cycle() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_users_sensitive_columns() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_subscription_fields() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.stamp_display_name_updated_at() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon, authenticated;
