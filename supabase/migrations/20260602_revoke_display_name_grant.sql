-- Revoke direct UPDATE on display_name from authenticated.
-- All display-name changes must go through the change_display_name RPC, which
-- enforces the 30-day cooldown and banned-name list. A direct PATCH via PostgREST
-- would bypass both checks.
revoke update (display_name) on public.users from authenticated;
