-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


revoke execute on function public.admin_adjust_user_xp(text, text, integer, integer, text, text) from anon, authenticated;
revoke execute on function public.admin_adjust_user_xp(text, uuid, integer, integer, text, text) from anon, authenticated;
revoke execute on function public.admin_reset_cycle()                       from anon, authenticated;
revoke execute on function public.append_new_drug_to_cycle()                from anon, authenticated;
revoke execute on function public.archive_and_reset_weekly_xp()             from anon, authenticated;
revoke execute on function public.claim_challenge_drug(date, text)          from anon, authenticated;
revoke execute on function public.fill_challenge_buffer(integer)            from anon, authenticated;
revoke execute on function public.maybe_reset_weekly_xp()                   from anon, authenticated;
revoke execute on function public.rls_auto_enable()                         from anon, authenticated;
revoke execute on function public.guard_users_sensitive_columns()           from anon, authenticated;
revoke execute on function public.handle_new_auth_user()                    from anon, authenticated;
