-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Returns clock + challenge data in one object.
-- Always returns a row (clock fields are never null), challenge fields are null if no row today.
-- Key is current_challenge_date (matches Schedule.jsx expectations).
CREATE OR REPLACE FUNCTION get_current_challenge()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$
  WITH et AS (
    SELECT NOW() AT TIME ZONE 'America/New_York' AS now_et
  ),
  clock AS (
    SELECT
      current_challenge_date()                              AS today,
      EXTRACT(HOUR   FROM now_et)::int                     AS et_hour,
      EXTRACT(MINUTE FROM now_et)::int                     AS et_minute,
      CASE
        WHEN EXTRACT(HOUR FROM now_et) < 4
          THEN CEIL(EXTRACT(EPOCH FROM (
            date_trunc('day', now_et) + INTERVAL '4 hours' - now_et
          )) / 60)::int
        ELSE CEIL(EXTRACT(EPOCH FROM (
          date_trunc('day', now_et) + INTERVAL '1 day 4 hours' - now_et
        )) / 60)::int
      END AS minutes_until
    FROM et
  ),
  ch AS (
    SELECT drug_id, title, difficulty, xp_base
    FROM daily_challenges
    WHERE challenge_date = current_challenge_date()
    LIMIT 1
  )
  SELECT jsonb_build_object(
    'current_challenge_date',        clock.today,
    'minutes_until_next_et_boundary', clock.minutes_until,
    'server_et_hour',                clock.et_hour,
    'server_et_minute',              clock.et_minute,
    'drug_id',                       ch.drug_id,
    'title',                         ch.title,
    'difficulty',                    ch.difficulty,
    'xp_base',                       ch.xp_base
  )
  FROM clock
  LEFT JOIN ch ON true;
$$;
