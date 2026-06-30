-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Seed the shuffle queue (empty = will generate on first auto-fill)
INSERT INTO app_settings (key, value)
VALUES ('challenge_cycle_remaining', '[]'::jsonb)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION auto_fill_challenge_schedule(
  p_days_ahead integer DEFAULT 30
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
  -- Collect unassigned future dates, ascending
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

  -- Load persisted queue
  SELECT value INTO v_raw FROM app_settings WHERE key = 'challenge_cycle_remaining';
  IF v_raw IS NOT NULL AND jsonb_array_length(v_raw) > 0 THEN
    SELECT array_agg(x ORDER BY ord)
    INTO v_queue
    FROM jsonb_array_elements_text(v_raw) WITH ORDINALITY AS t(x, ord);
  END IF;

  FOREACH v_date IN ARRAY v_dates LOOP
    IF array_length(v_queue, 1) IS NOT NULL THEN
      -- Mid-cycle: append any drugs added since this cycle started
      -- (not already in queue AND not already in a future scheduled slot)
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
      -- Queue exhausted — start a new cycle with a full shuffle
      SELECT array_agg(id ORDER BY random()) INTO v_queue FROM drugs;
    END IF;

    -- Pop the first drug
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

  -- Persist updated queue
  INSERT INTO app_settings (key, value)
  VALUES ('challenge_cycle_remaining', to_jsonb(v_queue))
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  RETURN jsonb_build_object('filled', v_filled);
END;
$$;
