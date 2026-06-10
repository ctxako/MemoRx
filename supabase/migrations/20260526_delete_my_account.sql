-- ───────────────────────────────────────────────────────────────────────────
-- Migration: delete_my_account()
-- Run in Supabase SQL editor. Required for App Store Guideline 5.1.1(v)
-- (in-app account deletion for apps using Sign in with Apple).
--
-- SECURITY DEFINER so the function can delete the caller's auth.users row.
-- Caller is identified strictly by `auth.uid()`; no parameters are accepted,
-- which means there is no way for a malicious client to delete a different user.
-- ───────────────────────────────────────────────────────────────────────────

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'delete_my_account: no authenticated user';
  end if;

  -- Owned data. Order matters only where there are FKs without ON DELETE CASCADE;
  -- the existing schema declares ON DELETE CASCADE from auth.users to public.users
  -- and from auth.users to drug_progress / quiz_attempts / drug_submissions, so
  -- the final auth.users delete would handle most of this. We still wipe explicitly
  -- so server-state is gone even if any FK is later loosened, and to cover tables
  -- (daily_completions, user_milestone_claims) that may not declare CASCADE.

  delete from public.drug_progress where user_id = v_uid;
  delete from public.quiz_attempts where user_id = v_uid;
  delete from public.drug_submissions where user_id = v_uid;

  -- daily_completions and user_milestone_claims may or may not exist depending on
  -- migration history; guard so the function is safe to run regardless.
  if to_regclass('public.daily_completions') is not null then
    execute 'delete from public.daily_completions where user_id = $1' using v_uid;
  end if;
  if to_regclass('public.user_milestone_claims') is not null then
    execute 'delete from public.user_milestone_claims where user_id = $1' using v_uid;
  end if;

  delete from public.users where id = v_uid;

  -- Finally: remove the auth row. After this, the JWT held by the client is
  -- effectively dead — any subsequent RPC will fail auth.
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'App Store 5.1.1(v) in-app account deletion. Removes all rows owned by auth.uid() and finally the auth.users row itself.';
