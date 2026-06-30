-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


create or replace view public.leaderboard_public
with (security_invoker = true) as
select
  id,
  legacy_user_id,
  display_name,
  total_xp,
  weekly_xp,
  streak,
  level_title,
  drugs_studied
from public.users
where lower(btrim(display_name)) not like '%signed out%';

grant select on public.leaderboard_public to authenticated;
