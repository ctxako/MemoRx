-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Fix 1: claim_challenge_drug — put the swapped-out drug back in the queue tail.
CREATE OR REPLACE FUNCTION public.claim_challenge_drug(
  p_challenge_date date,
  p_drug_id        text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_drug text;
BEGIN
  SELECT drug_id INTO v_old_drug
  FROM daily_challenges
  WHERE challenge_date = p_challenge_date;

  BEGIN
    INSERT INTO daily_challenges (challenge_date, drug_id)
    VALUES (p_challenge_date, p_drug_id)
    ON CONFLICT (challenge_date) DO UPDATE
      SET drug_id    = EXCLUDED.drug_id,
          updated_at = now();
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;

  UPDATE app_settings
  SET value = COALESCE(
    (SELECT jsonb_agg(elem)
     FROM jsonb_array_elements_text(value) AS elem
     WHERE elem <> p_drug_id),
    '[]'::jsonb
  )
  WHERE key = 'challenge_cycle_remaining';

  IF v_old_drug IS NOT NULL AND v_old_drug <> p_drug_id THEN
    UPDATE app_settings
    SET value = CASE
      WHEN value @> to_jsonb(v_old_drug) THEN value
      ELSE value || to_jsonb(v_old_drug)
    END
    WHERE key = 'challenge_cycle_remaining';
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Fix 2: auto_fill_challenge_schedule — fix new-drug detection to check all dates.
CREATE OR REPLACE FUNCTION public.auto_fill_challenge_schedule(
  p_days_ahead integer DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today    date    := current_challenge_date();
  v_queue    text[]  := ARRAY[]::text[];
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

  SELECT value INTO v_raw FROM app_settings WHERE key = 'challenge_cycle_remaining';
  IF v_raw IS NOT NULL AND jsonb_array_length(v_raw) > 0 THEN
    SELECT array_agg(x ORDER BY ord)
    INTO v_queue
    FROM jsonb_array_elements_text(v_raw) WITH ORDINALITY AS t(x, ord);
  END IF;

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
      SELECT array_agg(d.id) INTO v_missing
      FROM drugs d
      WHERE d.id <> ALL(v_queue)
        AND NOT EXISTS (
          SELECT 1 FROM daily_challenges dc WHERE dc.drug_id = d.id
        );
      IF v_missing IS NOT NULL THEN
        v_queue := v_queue || v_missing;
      END IF;
    ELSE
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
