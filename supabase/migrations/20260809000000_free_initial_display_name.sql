-- Let the first display_name set (NULL → value) skip the 30-day cooldown stamp.
-- Only stamp display_name_updated_at when old.display_name was already non-NULL,
-- so users who pick a name during onboarding don't burn their one free rename.

begin;

create or replace function public.stamp_display_name_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.display_name is distinct from old.display_name
     and old.display_name is not null then
    new.display_name_updated_at := now();
  end if;
  return new;
end;
$$;

commit;
