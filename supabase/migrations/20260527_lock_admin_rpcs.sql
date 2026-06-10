-- ───────────────────────────────────────────────────────────────────────────
-- Migration: lock_admin_rpcs
--
-- WHY: Every SECURITY DEFINER admin / internal-utility RPC in `public` was
-- callable by the `anon` and `authenticated` roles via PostgREST
-- (`/rest/v1/rpc/<fn>`). The anon key ships in every iOS binary, so any
-- attacker could obtain a JWT and:
--   • admin_adjust_user_xp(...)         — set any user's total_xp / weekly_xp
--                                         to any value (p_admin_id is just
--                                         logged, not verified).
--   • admin_reset_cycle()               — wipe the future-schedule buffer
--                                         and reshuffle the daily cycle.
--   • claim_challenge_drug(date, id)    — overwrite any future day's daily
--                                         drug to anything in the catalog.
--   • archive_and_reset_weekly_xp() /
--     maybe_reset_weekly_xp()            — zero everyone's weekly_xp on
--                                         Mondays (the latter without an
--                                         archive to weekly_results).
--   • fill_challenge_buffer(int)         — benign on its own (idempotent),
--                                         but exposed.
--
-- The user-facing RPCs that the iOS app DOES call —
--   submit_daily_completion, get_current_challenge, claim_apple_user,
--   delete_my_account, reset_my_progress, is_display_name_available —
-- already validate the caller via auth.uid() and stay executable.
--
-- HOW: Revoke EXECUTE from `anon` and `authenticated` on every privileged
-- RPC. The functions remain SECURITY DEFINER and callable by service_role
-- (Supabase dashboard, cron jobs, server-side code) and the table owner
-- (postgres). Cron jobs running as service_role continue to work
-- unchanged.
--
-- IDEMPOTENT: REVOKE is declarative — safe to re-run.
--
-- VERIFICATION (run after applying):
--
--   SELECT p.proname,
--          array_agg(DISTINCT acl.grantee::regrole::text) AS grantees
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   LEFT JOIN LATERAL aclexplode(p.proacl)
--     AS acl(grantor, grantee, privilege, grantable) ON TRUE
--   WHERE n.nspname = 'public'
--     AND p.proname IN (
--       'admin_adjust_user_xp','admin_reset_cycle','append_new_drug_to_cycle',
--       'archive_and_reset_weekly_xp','claim_challenge_drug','fill_challenge_buffer',
--       'maybe_reset_weekly_xp','rls_auto_enable','guard_users_sensitive_columns',
--       'handle_new_auth_user'
--     )
--   GROUP BY p.proname
--   ORDER BY p.proname;
--
-- Expected: grantees = {-, postgres, service_role} for every row. No anon,
-- no authenticated.
-- ───────────────────────────────────────────────────────────────────────────

begin;

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

commit;

-- ───────────────────────────────────────────────────────────────────────────
-- ROLLBACK (only if a legitimate server-side caller needs anon/authenticated
-- execute, which it should not — admin work belongs to service_role).
-- ───────────────────────────────────────────────────────────────────────────
-- begin;
-- grant execute on function public.admin_adjust_user_xp(text, text, integer, integer, text, text) to anon, authenticated;
-- grant execute on function public.admin_adjust_user_xp(text, uuid, integer, integer, text, text) to anon, authenticated;
-- grant execute on function public.admin_reset_cycle()                       to anon, authenticated;
-- grant execute on function public.append_new_drug_to_cycle()                to anon, authenticated;
-- grant execute on function public.archive_and_reset_weekly_xp()             to anon, authenticated;
-- grant execute on function public.claim_challenge_drug(date, text)          to anon, authenticated;
-- grant execute on function public.fill_challenge_buffer(integer)            to anon, authenticated;
-- grant execute on function public.maybe_reset_weekly_xp()                   to anon, authenticated;
-- grant execute on function public.rls_auto_enable()                         to anon, authenticated;
-- grant execute on function public.guard_users_sensitive_columns()           to anon, authenticated;
-- grant execute on function public.handle_new_auth_user()                    to anon, authenticated;
-- commit;
