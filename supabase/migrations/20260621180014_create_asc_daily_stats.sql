-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.asc_daily_stats (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  report_date DATE NOT NULL,
  app_name TEXT NOT NULL,
  installs INTEGER NOT NULL DEFAULT 0,
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(report_date, app_name)
);

ALTER TABLE public.asc_daily_stats ENABLE ROW LEVEL SECURITY;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'fetch-asc-data';

SELECT cron.schedule(
  'fetch-asc-data',
  '45 10 * * *',
  $cmd$SELECT net.http_post(
    url := 'https://edkyksduuzszahqidntq.supabase.co/functions/v1/fetch-asc-data',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb
  )$cmd$
);
