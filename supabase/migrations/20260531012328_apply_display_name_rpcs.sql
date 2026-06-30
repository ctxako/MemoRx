-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Re-apply is_display_name_available (CREATE OR REPLACE, idempotent)
create or replace function public.is_display_name_available(p_name text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_banned boolean := false;
begin
  if not (
    length(p_name) between 2 and 20
    and p_name ~ '^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$'
    and p_name !~ '  '
  ) then
    return false;
  end if;

  if to_regclass('public.banned_usernames') is not null then
    execute
      'select exists(select 1 from public.banned_usernames where lower(username) = lower($1))'
      into v_banned using p_name;
    if v_banned then return false; end if;
  end if;

  return not exists(
    select 1 from public.users where display_name = p_name::citext
  );
end;
$$;

revoke all on function public.is_display_name_available(text) from public;
grant execute on function public.is_display_name_available(text) to authenticated, anon;


-- Create change_display_name RPC
create or replace function public.change_display_name(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid          uuid := auth.uid();
  v_current_name public.citext;
  v_updated_at   timestamp;
  v_unlock_date  timestamp;
  v_banned       boolean := false;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  if not (
    length(p_name) between 2 and 20
    and p_name ~ '^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$'
    and p_name !~ '  '
  ) then
    return jsonb_build_object('success', false, 'error', 'invalid_format');
  end if;

  if to_regclass('public.banned_usernames') is not null then
    execute
      'select exists(select 1 from public.banned_usernames where lower(username) = lower($1))'
      into v_banned using p_name;
    if v_banned then
      return jsonb_build_object('success', false, 'error', 'banned');
    end if;
  end if;

  select display_name, display_name_updated_at
    into v_current_name, v_updated_at
    from public.users
    where id = v_uid;

  if v_current_name is distinct from p_name::public.citext then
    if v_updated_at is not null then
      v_unlock_date := v_updated_at + interval '30 days';
      if now() < v_unlock_date then
        return jsonb_build_object(
          'success',   false,
          'error',     'cooldown',
          'unlock_at', to_char(v_unlock_date at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        );
      end if;
    end if;

    if exists(
      select 1 from public.users
      where display_name = p_name::public.citext
        and id != v_uid
    ) then
      return jsonb_build_object('success', false, 'error', 'name_taken');
    end if;
  end if;

  update public.users
    set display_name = p_name::public.citext
    where id = v_uid;

  return jsonb_build_object('success', true);

exception
  when unique_violation then
    return jsonb_build_object('success', false, 'error', 'name_taken');
end;
$$;

revoke all on function public.change_display_name(text) from public;
grant execute on function public.change_display_name(text) to authenticated;
