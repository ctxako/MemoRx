-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.
--
-- REDACTED 2026-06-30: the original submission hardcoded this role's password in
-- plaintext. That value was rotated live (ALTER ROLE) before this archive was
-- committed; the password below is a placeholder only, not the real credential.

create schema if not exists ops;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'ops_watch_ro') then
    create role ops_watch_ro with login password '__REDACTED_ROTATED_2026-06-30__'
      nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  end if;
end $$;

grant usage on schema ops to ops_watch_ro;

create or replace function ops.overnight_metrics()
returns json
language sql
security definer
set search_path = ''
as $fn$
  select json_build_object(
    'signups_24h',       (select count(*) from auth.users
                            where created_at >= now() - interval '24 hours'),
    'trials_24h',        (select count(*) from public.users
                            where trial_started_at >= now() - interval '24 hours'),
    'conversions_24h',   (select count(*) from public.users
                            where subscription_started_at >= now() - interval '24 hours'
                              and subscription_status in ('active','lifetime')),
    'churn_24h',         (select count(*) from public.users
                            where subscription_status = 'expired'
                              and subscription_expires_at >= now() - interval '24 hours'),
    'quiz_attempts_24h', (select count(*) from public.quiz_attempts
                            where "timestamp" >= now() - interval '24 hours'),
    'daily_done_24h',    (select count(*) from public.daily_completions
                            where completed_at >= now() - interval '24 hours'),
    'drugs_total',       (select count(*) from public.drugs)
  );
$fn$;

revoke all on function ops.overnight_metrics() from public;
grant execute on function ops.overnight_metrics() to ops_watch_ro;
