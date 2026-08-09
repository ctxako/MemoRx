-- Tear down the dead ASC Daily Stats pipeline.
-- The fetch-asc-data cron + edge function never worked reliably
-- (5s net.http_post timeout vs 12s cold start; ASC 404s on zero-download days).
-- 4 rows written on 2026-06-20, nothing since.

-- 1. Unschedule the cron job (no-op if already gone)
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'fetch-asc-data';

-- 2. Remove the vault secret the cron job used for its x-asc-key header
DELETE FROM vault.secrets WHERE name = 'asc_cron_secret';

-- 3. Drop the table
DROP TABLE IF EXISTS public.asc_daily_stats;
