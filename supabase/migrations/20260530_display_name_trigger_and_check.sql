-- ───────────────────────────────────────────────────────────────────────────
-- Migration: display_name_updated_at auto-stamp trigger + format CHECK
--
-- WHY: The 30-day username cooldown reads display_name_updated_at. Without
-- this trigger, that column stays NULL forever → cooldown never fires →
-- unlimited name changes. The CHECK constraint is belt-and-suspenders
-- server-side validation matching the iOS regex.
--
-- IDEMPOTENT: safe to re-run (CREATE OR REPLACE, IF NOT EXISTS).
-- ───────────────────────────────────────────────────────────────────────────

begin;

-- 1. Auto-stamp display_name_updated_at whenever display_name actually changes.
create or replace function public.stamp_display_name_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.display_name is distinct from old.display_name then
    new.display_name_updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_display_name_updated_at on public.users;
create trigger trg_display_name_updated_at
  before update on public.users
  for each row execute function public.stamp_display_name_updated_at();

-- 2. Server-side format CHECK on display_name.
-- Allows NULL (admin-cleared names). When non-NULL: 2-20 chars, alphanum +
-- single spaces, must start and end with alphanum.
-- Uses citext::text cast so the regex sees the raw string.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_display_name_format'
  ) then
    alter table public.users
      add constraint users_display_name_format
      check (
        display_name is null
        or (
          length(display_name::text) between 2 and 20
          and display_name::text ~ '^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$'
          and display_name::text !~ '  '
        )
      );
  end if;
end $$;

-- 3. Re-enable the unique index on display_name if it was dropped.
-- The schema doc says it was dropped 2026-05-14, but we want strict uniqueness.
create unique index if not exists users_display_name_unique
  on public.users (display_name)
  where display_name is not null;

commit;
