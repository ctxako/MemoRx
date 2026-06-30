-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


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
create unique index if not exists users_display_name_unique
  on public.users (display_name)
  where display_name is not null;
