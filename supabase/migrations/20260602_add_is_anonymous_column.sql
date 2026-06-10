-- Track is_anonymous column that was added directly in the dashboard.
-- The handle_new_auth_user trigger inserts is_anonymous = true for every new
-- sign-in; without this column the trigger errors and anonymous sessions cannot
-- create a user row.
alter table public.users
  add column if not exists is_anonymous boolean not null default false;
