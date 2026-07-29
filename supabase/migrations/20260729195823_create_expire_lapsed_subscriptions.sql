-- Server-side sweep for lapsed trials and active subscriptions.
-- Runs every 6 hours via pg_cron (direct SQL, no HTTP).
-- Never touches is_lifetime; lifetime users have subscription_expires_at = NULL.

CREATE OR REPLACE FUNCTION public.expire_lapsed_subscriptions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.users
     SET subscription_status = 'expired'
   WHERE subscription_status IN ('trial', 'active')
     AND subscription_expires_at IS NOT NULL
     AND subscription_expires_at < now();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.expire_lapsed_subscriptions() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'expire-lapsed-subs',
  '0 */6 * * *',
  $$SELECT public.expire_lapsed_subscriptions()$$
);
