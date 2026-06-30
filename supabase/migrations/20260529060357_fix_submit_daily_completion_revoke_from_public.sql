-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Previous revoke-from-anon was ineffective: anon inherits EXECUTE via the
-- default PUBLIC grant. Revoke from PUBLIC and grant back only to the roles
-- that should call it.
REVOKE EXECUTE ON FUNCTION
  public.submit_daily_completion(uuid, text, integer, integer)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.submit_daily_completion(uuid, text, integer, integer)
TO authenticated, service_role;
