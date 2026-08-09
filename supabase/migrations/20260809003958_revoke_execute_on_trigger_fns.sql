-- Trigger functions should only fire in trigger context, never as RPCs.
-- Revoke from PUBLIC (the Postgres default), which cascades to anon/authenticated.
-- Also drops the orphaned set_display_name_updated_at (no trigger references it).

revoke execute on function public.append_new_drug_to_cycle()       from public, anon, authenticated;
revoke execute on function public.check_challenge_locked()          from public, anon, authenticated;
revoke execute on function public.guard_subscription_fields()       from public, anon, authenticated;
revoke execute on function public.guard_users_sensitive_columns()   from public, anon, authenticated;
revoke execute on function public.handle_new_auth_user()            from public, anon, authenticated;
revoke execute on function public.kb_update_timestamp()             from public, anon, authenticated;
revoke execute on function public.stamp_display_name_updated_at()   from public, anon, authenticated;

drop function if exists public.set_display_name_updated_at();
