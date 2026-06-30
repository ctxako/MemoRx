-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Returns drugs still available in the current cycle's bank.
-- If the bank is empty a new cycle is implied; returns all drugs not already in future slots.
CREATE OR REPLACE FUNCTION get_available_cycle_drugs()
RETURNS TABLE(id text, generic_name text) LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_queue jsonb;
  v_today date := current_challenge_date();
BEGIN
  SELECT value INTO v_queue FROM app_settings WHERE key = 'challenge_cycle_remaining';

  IF v_queue IS NULL OR jsonb_array_length(v_queue) = 0 THEN
    -- Bank exhausted: show all drugs not already in a future slot
    RETURN QUERY
      SELECT d.id, d.generic_name FROM drugs d
      WHERE NOT EXISTS (
        SELECT 1 FROM daily_challenges dc
        WHERE dc.drug_id = d.id AND dc.challenge_date > v_today
      )
      ORDER BY d.generic_name;
  ELSE
    -- Only show drugs that are in the queue AND not already manually scheduled
    RETURN QUERY
      SELECT d.id, d.generic_name FROM drugs d
      WHERE d.id IN (SELECT jsonb_array_elements_text(v_queue))
        AND NOT EXISTS (
          SELECT 1 FROM daily_challenges dc
          WHERE dc.drug_id = d.id AND dc.challenge_date > v_today
        )
      ORDER BY d.generic_name;
  END IF;
END;
$$;

-- Upsert a challenge AND claim the drug from the bank in one atomic call.
CREATE OR REPLACE FUNCTION claim_challenge_drug(
  p_challenge_date date,
  p_drug_id        text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  BEGIN
    INSERT INTO daily_challenges (challenge_date, drug_id)
    VALUES (p_challenge_date, p_drug_id)
    ON CONFLICT (challenge_date) DO UPDATE
      SET drug_id = EXCLUDED.drug_id, updated_at = now();
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;

  -- Remove the drug from the cycle bank so auto-fill won't use it again this cycle
  UPDATE app_settings
  SET value = COALESCE(
    (SELECT jsonb_agg(elem)
     FROM jsonb_array_elements_text(value) AS elem
     WHERE elem <> p_drug_id),
    '[]'::jsonb
  )
  WHERE key = 'challenge_cycle_remaining';

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Update auto_fill to clean manually-assigned drugs from the queue first,
-- then also handle new drugs appended mid-cycle.
CREATE OR REPLACE FUNCTION auto_fill_challenge_schedule(
  p_days_ahead integer DEFAULT 90
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_today    date := current_challenge_date();
  v_queue    text[] := ARRAY[]::text[];
  v_raw      jsonb;
  v_missing  text[];
  v_date     date;
  v_drug_id  text;
  v_filled   integer := 0;
  v_dates    date[];
BEGIN
  SELECT array_agg(d ORDER BY d) INTO v_dates
  FROM (
    SELECT (v_today + gs)::date AS d
    FROM generate_series(1, p_days_ahead) AS gs
  ) t
  WHERE NOT EXISTS (
    SELECT 1 FROM daily_challenges dc WHERE dc.challenge_date = t.d
  );

  IF v_dates IS NULL THEN
    RETURN jsonb_build_object('filled', 0);
  END IF;

  -- Load queue
  SELECT value INTO v_raw FROM app_settings WHERE key = 'challenge_cycle_remaining';
  IF v_raw IS NOT NULL AND jsonb_array_length(v_raw) > 0 THEN
    SELECT array_agg(x ORDER BY ord)
    INTO v_queue
    FROM jsonb_array_elements_text(v_raw) WITH ORDINALITY AS t(x, ord);
  END IF;

  -- Remove any drugs that were manually claimed (already in a future slot)
  IF array_length(v_queue, 1) IS NOT NULL THEN
    SELECT array_agg(q_id ORDER BY ord)
    INTO v_queue
    FROM unnest(v_queue) WITH ORDINALITY AS t(q_id, ord)
    WHERE NOT EXISTS (
      SELECT 1 FROM daily_challenges dc
      WHERE dc.drug_id = t.q_id AND dc.challenge_date > v_today
    );
  END IF;

  FOREACH v_date IN ARRAY v_dates LOOP
    IF array_length(v_queue, 1) IS NOT NULL THEN
      -- Append new drugs added since this cycle started
      SELECT array_agg(d.id) INTO v_missing
      FROM drugs d
      WHERE d.id <> ALL(v_queue)
        AND NOT EXISTS (
          SELECT 1 FROM daily_challenges dc
          WHERE dc.drug_id = d.id AND dc.challenge_date > v_today
        );
      IF v_missing IS NOT NULL THEN
        v_queue := v_queue || v_missing;
      END IF;
    ELSE
      -- New cycle: full shuffle
      SELECT array_agg(id ORDER BY random()) INTO v_queue FROM drugs;
    END IF;

    v_drug_id := v_queue[1];
    IF array_length(v_queue, 1) > 1 THEN
      v_queue := v_queue[2:array_length(v_queue, 1)];
    ELSE
      v_queue := ARRAY[]::text[];
    END IF;

    INSERT INTO daily_challenges (challenge_date, drug_id)
    VALUES (v_date, v_drug_id)
    ON CONFLICT (challenge_date) DO NOTHING;

    v_filled := v_filled + 1;
  END LOOP;

  INSERT INTO app_settings (key, value)
  VALUES ('challenge_cycle_remaining', to_jsonb(v_queue))
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  RETURN jsonb_build_object('filled', v_filled);
END;
$$;

-- get_current_challenge: auto-fill if tomorrow is unassigned (free-tier autonomous trigger)
CREATE OR REPLACE FUNCTION get_current_challenge()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER AS $$
DECLARE
  v_today  date;
  v_et     timestamptz;
  v_ch     record;
  v_result jsonb;
BEGIN
  v_today := current_challenge_date();
  v_et    := NOW() AT TIME ZONE 'America/New_York';

  -- Auto-fill if tomorrow has no challenge scheduled
  IF NOT EXISTS (
    SELECT 1 FROM daily_challenges WHERE challenge_date = v_today + 1
  ) THEN
    PERFORM auto_fill_challenge_schedule(90);
  END IF;

  SELECT drug_id INTO v_ch FROM daily_challenges WHERE challenge_date = v_today LIMIT 1;

  SELECT jsonb_build_object(
    'current_challenge_date',         v_today,
    'minutes_until_next_et_boundary',
      CASE
        WHEN EXTRACT(HOUR FROM v_et) < 4
          THEN CEIL(EXTRACT(EPOCH FROM (date_trunc('day', v_et) + INTERVAL '4 hours' - v_et)) / 60)::int
        ELSE CEIL(EXTRACT(EPOCH FROM (date_trunc('day', v_et) + INTERVAL '1 day 4 hours' - v_et)) / 60)::int
      END,
    'server_et_hour',   EXTRACT(HOUR   FROM v_et)::int,
    'server_et_minute', EXTRACT(MINUTE FROM v_et)::int,
    'drug_id',          v_ch.drug_id,
    'xp_base',          50
  ) INTO v_result;

  RETURN v_result;
END;
$$;
