-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


create table if not exists public.username_reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid not null references auth.users (id) on delete cascade,
  reported_id   uuid references auth.users (id) on delete set null,
  reported_name text not null,
  created_at    timestamptz not null default now()
);

-- One report per reporter-reported pair. Prevents spam.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.username_reports'::regclass
      and conname = 'username_reports_one_per_pair'
  ) then
    alter table public.username_reports
      add constraint username_reports_one_per_pair
      unique (reporter_id, reported_id);
  end if;
end $$;

alter table public.username_reports enable row level security;

-- Users can insert reports (only for themselves as reporter).
drop policy if exists "username_reports_insert" on public.username_reports;
create policy "username_reports_insert" on public.username_reports
  for insert with check (auth.uid() = reporter_id);

-- Users can see their own reports.
drop policy if exists "username_reports_select_own" on public.username_reports;
create policy "username_reports_select_own" on public.username_reports
  for select using (auth.uid() = reporter_id);

-- Reports are append-only for users; only service_role/admin can update or delete.
revoke update, delete on public.username_reports from authenticated;
revoke all on public.username_reports from anon;
grant insert, select on public.username_reports to authenticated;
