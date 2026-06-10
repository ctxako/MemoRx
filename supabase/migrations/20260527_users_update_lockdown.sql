-- ───────────────────────────────────────────────────────────────────────────
-- Migration: users_update_lockdown
--
-- WHY: Before this migration the policy
--
--     create policy "users_update" on public.users for update using (auth.uid() = id);
--
-- combined with full table-level UPDATE grants let any authenticated client
-- PATCH any column on its own row, including:
--   • is_lifetime (paid entitlement)
--   • total_xp, weekly_xp, streak, level, level_title, drugs_studied (leaderboard rank)
--   • apple_user_id / legacy_user_id (identity rebinding)
--
-- The anon key ships in every iOS binary. Anyone can produce a JWT for their
-- own account (anonymous or Apple sign-in) and `curl` a single PATCH to grant
-- themselves lifetime premium and #1 leaderboard. RLS row-scope alone is not
-- a defence against the user attacking their own row.
--
-- HOW: PostgreSQL supports per-column UPDATE privileges, and PostgREST
-- enforces them — a PATCH that touches a column the role does not have UPDATE
-- on is rejected. We revoke UPDATE on public.users from authenticated/anon
-- entirely, then re-grant UPDATE only on the columns clients actually need
-- to write directly (user preferences, profile prefs, last_active heartbeat,
-- onboarding flag). Everything else (XP, streak, entitlements, identity
-- linkage, server-managed columns) becomes RPC-only.
--
-- The existing RPCs already responsible for these writes are SECURITY DEFINER
-- and run as the table owner, so column-level grants on the `authenticated`
-- role do NOT affect them:
--   • public.submit_daily_completion(...)  -- XP, streak, weekly_xp, drugs_studied
--   • public.claim_apple_user(...)         -- apple_user_id, legacy_user_id linkage
--   • public.delete_my_account()           -- full row delete
--   • admin/comp grants                    -- is_lifetime
--   • public.handle_new_auth_user trigger  -- is_anonymous, created_at
--
-- ROW SCOPE: the existing `users_update` RLS policy (auth.uid() = id) stays in
-- place. Column GRANTs gate WHICH columns; RLS gates WHICH rows. Both apply.
--
-- IDEMPOTENT: safe to re-run. REVOKE/GRANT are declarative and converge.
--
-- Run in: Supabase dashboard → SQL editor (one shot).
--
-- CLIENT COUPLING: This migration is paired with a same-commit trim of the
-- Swift `UserProfileSafeRow` struct in
-- MemoRx/Services/SupabaseManager.swift and its sole constructor in
-- MemoRx/UserProgressService.swift. The struct now only carries the
-- columns listed in the GRANT below. Apply this migration AT OR BEFORE the
-- iOS release that ships those struct changes — applying it against an older
-- client will cause every `upsertUserProfile` call to 4xx with "permission
-- denied for column X".
--
-- ───────────────────────────────────────────────────────────────────────────

begin;

-- 0. Ensure `has_completed_onboarding` exists. This column is referenced both
--    by the iOS client (UserProfileSafeRow / upsertOnboardingCompleted) and by
--    the GRANT below. The original schema file had this as a separate ALTER
--    that may never have been run against your live project — make it safe to
--    apply this migration regardless.
alter table public.users
  add column if not exists has_completed_onboarding boolean not null default false;

-- 1. Strip table-level UPDATE from client roles. (We deliberately leave SELECT
--    and INSERT alone — both are still needed and are gated by their own RLS.)
revoke update on public.users from authenticated;
revoke update on public.users from anon;

-- 2. Re-grant UPDATE only on the columns clients write directly. Anything not
--    listed here can only be written by SECURITY DEFINER RPCs or service_role.
--
--    If you ADD a new client-writable column to public.users later, append it
--    to this grant — otherwise PostgREST will reject PATCHes touching it.
grant update (
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

-- 3. Defense in depth: a BEFORE UPDATE trigger that rejects any change to
--    sensitive columns from a non-service-role session. Belt-and-suspenders in
--    case a future migration accidentally re-grants table-level UPDATE.
--
--    The check is skipped when current_setting('role') resolves to one of the
--    privileged roles, so SECURITY DEFINER functions running as the table
--    owner (postgres / supabase_admin) and dashboard service_role queries
--    continue to work.
create or replace function public.guard_users_sensitive_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := current_user;
begin
  -- Bypass for table owner / service_role / postgres. Adjust if your owner differs.
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

commit;

-- ───────────────────────────────────────────────────────────────────────────
-- VERIFICATION
--
-- After running, paste each block below into the SQL editor (as the dashboard
-- service role) to confirm the lockdown is in place.
-- ───────────────────────────────────────────────────────────────────────────

-- A. Column grants — should show ONLY the 13 allow-listed columns for
--    authenticated, and nothing for anon.
-- select grantee, table_name, column_name, privilege_type
-- from information_schema.column_privileges
-- where table_schema = 'public'
--   and table_name = 'users'
--   and privilege_type = 'UPDATE'
--   and grantee in ('authenticated', 'anon')
-- order by grantee, column_name;

-- B. Functional test from the iOS app side — pull your own JWT from a running
--    debug session (UserDefaults `currentAccessToken` or the Supabase swift
--    SDK), then:
--
--      curl -X PATCH \
--        "https://edkyksduuzszahqidntq.supabase.co/rest/v1/users?id=eq.<your_uuid>" \
--        -H "apikey: $SUPABASE_ANON_KEY" \
--        -H "Authorization: Bearer $YOUR_JWT" \
--        -H "Content-Type: application/json" \
--        -H "Prefer: return=representation" \
--        -d '{"is_lifetime": true, "total_xp": 999999}'
--
--    Expected: 4xx error referencing missing UPDATE privilege OR a trigger
--    exception. NOT a 200 with the row reflected back.
--
--    Then confirm the legitimate path still works:
--
--      curl -X PATCH \
--        "https://edkyksduuzszahqidntq.supabase.co/rest/v1/users?id=eq.<your_uuid>" \
--        -H "apikey: $SUPABASE_ANON_KEY" \
--        -H "Authorization: Bearer $YOUR_JWT" \
--        -H "Content-Type: application/json" \
--        -d '{"selected_theme": "premium"}'
--
--    Expected: 204 no-content (or 200 with row if Prefer header set).

-- ───────────────────────────────────────────────────────────────────────────
-- ROLLBACK (if something legitimate breaks post-deploy)
-- ───────────────────────────────────────────────────────────────────────────
-- begin;
-- drop trigger if exists trg_guard_users_sensitive_columns on public.users;
-- drop function if exists public.guard_users_sensitive_columns();
-- grant update on public.users to authenticated;
-- commit;
