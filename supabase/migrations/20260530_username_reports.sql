-- ───────────────────────────────────────────────────────────────────────────
-- Migration: username_reports table
--
-- WHY: Lets users flag offensive leaderboard names for admin review.
-- reported_name is a snapshot — survives if the offender renames before
-- admin action. JOINs to users gives apple_given_name / apple_user_id
-- for identity context.
--
-- IDEMPOTENT: safe to re-run.
-- ───────────────────────────────────────────────────────────────────────────

begin;

create table if not exists public.username_reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid not null references auth.users (id) on delete cascade,
  reported_id   uuid not null references auth.users (id) on delete cascade,
  reported_name text not null,
  created_at    timestamptz not null default now()
);

-- One report per reporter-reported pair. Prevents spam; re-inserting is a
-- no-op (ON CONFLICT DO NOTHING on the client side, or just let it 409).
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

-- Users can see their own reports (optional — mostly for admin queries via
-- service_role which bypasses RLS).
drop policy if exists "username_reports_select_own" on public.username_reports;
create policy "username_reports_select_own" on public.username_reports
  for select using (auth.uid() = reporter_id);

-- Revoke write beyond INSERT from client roles. Reports are append-only for
-- users; only service_role/admin can update or delete.
revoke update, delete on public.username_reports from authenticated;
revoke all on public.username_reports from anon;
grant insert, select on public.username_reports to authenticated;

commit;

-- ───────────────────────────────────────────────────────────────────────────
-- ADMIN QUERY: review pending reports with offender identity context
-- ───────────────────────────────────────────────────────────────────────────
-- select
--   r.id as report_id,
--   r.reported_name,
--   r.created_at as reported_at,
--   u.display_name as current_name,
--   u.apple_given_name,
--   u.apple_user_id,
--   u.id as user_id
-- from public.username_reports r
-- join public.users u on u.id = r.reported_id
-- order by r.created_at desc;
--
-- ACTION: clear offending name (user keeps XP/streak, must pick new name):
--   update public.users set display_name = null where id = '<reported_user_id>';
-- ───────────────────────────────────────────────────────────────────────────
