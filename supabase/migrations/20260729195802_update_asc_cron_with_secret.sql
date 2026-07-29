-- Gate fetch-asc-data behind x-asc-key secret header.
-- Prerequisites:
--   1. Edge function secret: supabase secrets set ASC_CRON_SECRET=<value>
--   2. Vault secret (same value): SELECT vault.create_secret('<value>', 'asc_cron_secret');

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'fetch-asc-data';

SELECT cron.schedule(
  'fetch-asc-data',
  '45 10 * * *',
  $cmd$SELECT net.http_post(
    url     := 'https://edkyksduuzszahqidntq.supabase.co/functions/v1/fetch-asc-data',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-asc-key',   (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'asc_cron_secret')
    ),
    body    := '{}'::jsonb
  )$cmd$
);
