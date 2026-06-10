-- Backs up the reset_my_progress RPC that was created directly in the dashboard.
-- Clears all progress tables for the calling user and zeros XP/streak on users.
-- SECURITY DEFINER so it can DELETE from tables that have no client DELETE RLS policy.
create or replace function public.reset_my_progress()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  delete from drug_progress         where user_id = v_uid;
  delete from quiz_attempts         where user_id = v_uid;
  delete from daily_completions     where user_id = v_uid;
  delete from user_milestone_claims where user_id = v_uid;

  update users
     set total_xp  = 0,
         weekly_xp = 0,
         streak    = 0
   where id = v_uid;

  return jsonb_build_object('success', true);
end;
$$;

-- Only authenticated users may call this RPC (anon sessions have no progress to reset).
revoke execute on function public.reset_my_progress() from anon;
grant  execute on function public.reset_my_progress() to authenticated;
