-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Ensure has_completed_onboarding exists
alter table public.users
  add column if not exists has_completed_onboarding boolean not null default false;

-- 1. Strip table-level UPDATE from client roles
revoke update on public.users from authenticated;
revoke update on public.users from anon;

-- 2. Re-grant UPDATE only on client-writable columns
-- NOTE: display_name_updated_at is intentionally EXCLUDED — the
-- stamp_display_name_updated_at trigger (SECURITY DEFINER) writes it automatically.
grant update (
  display_name,
  student_level,
  student_level_title,
  naplex_date,
  flagged_drug_ids,
  daily_reminder_enabled,
  daily_reminder_hour,
  daily_reminder_minute,
  selected_theme,
  high_contrast_enabled,
  apple_given_name,
  start_date,
  last_active,
  has_completed_onboarding
) on public.users to authenticated;

-- 3. Defense-in-depth trigger
create or replace function public.guard_users_sensitive_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := current_user;
begin
  if v_role in ('postgres', 'supabase_admin', 'service_role', 'supabase_auth_admin') then
    return new;
  end if;

  if new.total_xp        is distinct from old.total_xp        then raise exception 'users.total_xp is server-managed';        end if;
  if new.weekly_xp       is distinct from old.weekly_xp       then raise exception 'users.weekly_xp is server-managed';       end if;
  if new.streak          is distinct from old.streak          then raise exception 'users.streak is server-managed';          end if;
  if new.level           is distinct from old.level           then raise exception 'users.level is server-managed';           end if;
  if new.level_title     is distinct from old.level_title     then raise exception 'users.level_title is server-managed';     end if;
  if new.drugs_studied   is distinct from old.drugs_studied   then raise exception 'users.drugs_studied is server-managed';   end if;
  if new.is_lifetime     is distinct from old.is_lifetime     then raise exception 'users.is_lifetime is admin-only';         end if;
  if new.apple_user_id   is distinct from old.apple_user_id   then raise exception 'users.apple_user_id is RPC-managed';      end if;
  if new.legacy_user_id  is distinct from old.legacy_user_id  then raise exception 'users.legacy_user_id is admin-managed';   end if;
  if new.id              is distinct from old.id              then raise exception 'users.id is immutable';                    end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_users_sensitive_columns on public.users;
create trigger trg_guard_users_sensitive_columns
  before update on public.users
  for each row execute function public.guard_users_sensitive_columns();
