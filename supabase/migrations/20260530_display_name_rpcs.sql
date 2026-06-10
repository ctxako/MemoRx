-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: display_name_rpcs
--
-- WHY (bugs fixed):
--   #2  isDisplayNameAvailable was querying users table directly. RLS
--       (auth.uid() = id) made it only see the caller's own row, so every
--       other name appeared "Available" regardless of whether it was taken.
--
--   #3  The 30-day rename cooldown was client-side only. A caller with their
--       JWT could PATCH users.display_name directly and skip the cooldown.
--
--   #9  The banned_usernames table was never consulted from Swift.
--
-- FIX: Two SECURITY DEFINER RPCs replace the direct table writes for display
-- name operations. Running as the table owner they bypass RLS, see the full
-- users table for uniqueness/cooldown checks, and can query banned_usernames.
--
-- IDEMPOTENT: CREATE OR REPLACE + REVOKE/GRANT are declarative; safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- ── 1. is_display_name_available(p_name text) → boolean ─────────────────────
-- Returns TRUE only when:
--   • Format is valid (2-20 chars, alphanum + single spaces, starts/ends alphanum)
--   • Name not in banned_usernames (if that table exists)
--   • No existing user holds this display_name (citext case-insensitive compare)

create or replace function public.is_display_name_available(p_name text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_banned boolean := false;
begin
  -- Format check
  if not (
    length(p_name) between 2 and 20
    and p_name ~ '^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$'
    and p_name !~ '  '
  ) then
    return false;
  end if;

  -- Banned usernames (table is optional)
  if to_regclass('public.banned_usernames') is not null then
    execute
      'select exists(select 1 from public.banned_usernames where lower(username) = lower($1))'
      into v_banned using p_name;
    if v_banned then return false; end if;
  end if;

  -- Uniqueness (citext does case-insensitive comparison automatically)
  return not exists(
    select 1 from public.users where display_name = p_name::citext
  );
end;
$$;

revoke all on function public.is_display_name_available(text) from public;
grant execute on function public.is_display_name_available(text) to authenticated, anon;


-- ── 2. change_display_name(p_name text) → jsonb ─────────────────────────────
-- Single server-authoritative entry point for all display-name changes.
-- Enforces format, 30-day cooldown, banned-name list, and uniqueness.
-- Returns: {"success": true}
--      or: {"success": false, "error": "<code>", "unlock_at": "<iso8601>"}
-- Error codes: not_authenticated | invalid_format | banned | cooldown | name_taken

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

  -- Format
  if not (
    length(p_name) between 2 and 20
    and p_name ~ '^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$'
    and p_name !~ '  '
  ) then
    return jsonb_build_object('success', false, 'error', 'invalid_format');
  end if;

  -- Banned names
  if to_regclass('public.banned_usernames') is not null then
    execute
      'select exists(select 1 from public.banned_usernames where lower(username) = lower($1))'
      into v_banned using p_name;
    if v_banned then
      return jsonb_build_object('success', false, 'error', 'banned');
    end if;
  end if;

  -- Read current name + cooldown timestamp (SECURITY DEFINER bypasses RLS)
  select display_name, display_name_updated_at
    into v_current_name, v_updated_at
    from public.users
    where id = v_uid;

  -- Cooldown + uniqueness only matter when the name is actually changing
  if v_current_name is distinct from p_name::public.citext then
    -- 30-day cooldown
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

    -- Uniqueness (check other rows only)
    if exists(
      select 1 from public.users
      where display_name = p_name::public.citext
        and id != v_uid
    ) then
      return jsonb_build_object('success', false, 'error', 'name_taken');
    end if;
  end if;

  -- Apply (trg_display_name_updated_at stamps display_name_updated_at automatically)
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

commit;
