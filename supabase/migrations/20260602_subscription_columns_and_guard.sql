-- Track subscription columns and the guard trigger that were created directly
-- in the Supabase dashboard. All writes to these columns are gated by the
-- guard_subscription_fields trigger below — only service_role (the
-- sync-subscription edge function) may update them.

-- Columns
alter table public.users
  add column if not exists subscription_status      text        not null default 'none',
  add column if not exists subscription_product_id  text,
  add column if not exists subscription_expires_at  timestamptz,
  add column if not exists subscription_started_at  timestamptz,
  add column if not exists trial_started_at         timestamptz,
  add column if not exists original_transaction_id  text;

-- Guard function: silently reverts subscription fields for any caller that is
-- not service_role. Runs as a BEFORE UPDATE trigger so the values are reset
-- before the row is written.
create or replace function public.guard_subscription_fields()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user != 'service_role' then
    new.subscription_status      := old.subscription_status;
    new.subscription_product_id  := old.subscription_product_id;
    new.subscription_expires_at  := old.subscription_expires_at;
    new.trial_started_at         := old.trial_started_at;
    new.subscription_started_at  := old.subscription_started_at;
    new.original_transaction_id  := old.original_transaction_id;
    new.is_lifetime               := old.is_lifetime;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_subscription_fields on public.users;
create trigger guard_subscription_fields
  before update on public.users
  for each row execute function public.guard_subscription_fields();
